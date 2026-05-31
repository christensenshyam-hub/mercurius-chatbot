import Testing
import Foundation
import NetworkingKit
@testable import ImageUploadFeature

// State-machine tests for `ImageUploadViewModel`, driven entirely through stub
// dependencies (no UIKit, no network) so they run on the macOS command line.
// Covers: selection, the happy upload path, the duplicate-upload guard, retry
// behavior (retryable vs not), and every failure surface (prepare, network,
// session).

// MARK: - Fixtures + stubs

private let sampleData = Data([0x01, 0x02, 0x03, 0x04])
private let sampleInput = APIClient.ImageUploadInput(contentType: "image/jpeg", base64Data: "QUJDRA==", fileName: nil)
private let sampleResponse = APIClient.ImageUploadResponse(
    id: "img_1",
    url: "/api/images/img_1",
    contentType: "image/jpeg",
    fileName: nil,
    size: 4,
    createdAt: "2026-05-30T12:00:00.000Z"
)

private struct TestError: Error {}

/// Records calls and returns a fixed outcome. An actor so `callCount` is safe to
/// read from the test after an upload runs off the main actor.
private actor StubUploader: ImageUploading {
    enum Outcome {
        case success(APIClient.ImageUploadResponse)
        case failure(APIError)
    }

    let outcome: Outcome
    private(set) var callCount = 0
    private(set) var lastInput: APIClient.ImageUploadInput?

    init(_ outcome: Outcome) { self.outcome = outcome }

    func uploadImage(_ input: APIClient.ImageUploadInput, sessionId: String) async throws -> APIClient.ImageUploadResponse {
        callCount += 1
        lastInput = input
        switch outcome {
        case let .success(response): return response
        case let .failure(error): throw error
        }
    }
}

private struct StubPreparer: ImagePreparing {
    enum Behavior {
        case succeed(APIClient.ImageUploadInput)
        case fail(ImagePreparationError)
    }
    let behavior: Behavior

    func prepare(imageData: Data, fileName: String?) throws -> APIClient.ImageUploadInput {
        switch behavior {
        case let .succeed(input): return input
        case let .fail(error): throw error
        }
    }
}

@MainActor
private func makeViewModel(
    uploader: ImageUploading,
    preparer: ImagePreparing = StubPreparer(behavior: .succeed(sampleInput)),
    sessionIdProvider: @escaping @Sendable () throws -> String = { "sess_test_1234" }
) -> ImageUploadViewModel {
    ImageUploadViewModel(uploader: uploader, preparer: preparer, sessionIdProvider: sessionIdProvider)
}

/// Poll until the upload settles (no longer in flight), or give up after ~2s.
@MainActor
private func settle(_ vm: ImageUploadViewModel) async {
    for _ in 0..<400 {
        if !vm.isUploading { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

// MARK: - Tests

@MainActor
@Suite("ImageUploadViewModel")
struct ImageUploadViewModelTests {

    @Test("Initial state is idle with no selection")
    func initialState() {
        let vm = makeViewModel(uploader: StubUploader(.success(sampleResponse)))
        #expect(vm.phase == .idle)
        #expect(vm.selectedImageData == nil)
        #expect(vm.canUpload == false)
        #expect(vm.isUploading == false)
    }

    @Test("select() holds the bytes and becomes ready to upload")
    func selectReadiesUpload() {
        let vm = makeViewModel(uploader: StubUploader(.success(sampleResponse)))
        vm.select(data: sampleData, fileName: "photo.heic")
        #expect(vm.selectedImageData == sampleData)
        #expect(vm.selectedFileName == "photo.heic")
        #expect(vm.phase == .idle)
        #expect(vm.canUpload == true)
    }

    @Test("Happy path: idle → uploading → uploaded, with prepared input sent")
    func happyPath() async {
        let uploader = StubUploader(.success(sampleResponse))
        let vm = makeViewModel(uploader: uploader)
        vm.select(data: sampleData, fileName: nil)

        vm.upload()
        #expect(vm.isUploading)              // synchronous transition

        await settle(vm)
        #expect(vm.phase == .uploaded(sampleResponse))
        #expect(vm.uploadedResponse == sampleResponse)
        #expect(await uploader.callCount == 1)
        #expect(await uploader.lastInput == sampleInput)
    }

    @Test("upload() with no selection is a no-op")
    func uploadWithoutSelection() async {
        let uploader = StubUploader(.success(sampleResponse))
        let vm = makeViewModel(uploader: uploader)
        vm.upload()
        await settle(vm)
        #expect(vm.phase == .idle)
        #expect(await uploader.callCount == 0)
    }

    @Test("Duplicate uploads are blocked while one is in flight")
    func duplicateGuard() async {
        let uploader = StubUploader(.success(sampleResponse))
        let vm = makeViewModel(uploader: uploader)
        vm.select(data: sampleData, fileName: nil)

        vm.upload()   // phase → uploading; task spawned but not yet run
        vm.upload()   // guard: no-op
        vm.upload()   // guard: no-op

        await settle(vm)
        #expect(await uploader.callCount == 1, "only one upload should have run")
    }

    @Test("Preparation failure surfaces a non-retryable error and never hits the network")
    func prepareFailure() async {
        let uploader = StubUploader(.success(sampleResponse))
        let preparer = StubPreparer(behavior: .fail(.tooLargeAfterCompression))
        let vm = makeViewModel(uploader: uploader, preparer: preparer)
        vm.select(data: sampleData, fileName: nil)

        vm.upload()
        await settle(vm)

        #expect(vm.failureReason == ImagePreparationError.tooLargeAfterCompression.userMessage)
        #expect(vm.canRetry == false)
        #expect(await uploader.callCount == 0)
    }

    @Test("Retryable network failure can be retried, firing another upload")
    func retryableFailure() async {
        let uploader = StubUploader(.failure(.server(status: 500)))
        let vm = makeViewModel(uploader: uploader)
        vm.select(data: sampleData, fileName: nil)

        vm.upload()
        await settle(vm)
        #expect(vm.canRetry == true)
        #expect(await uploader.callCount == 1)

        vm.retry()
        await settle(vm)
        #expect(await uploader.callCount == 2)
    }

    @Test("Non-retryable failure hides retry, and retry() is a no-op")
    func nonRetryableFailure() async {
        let uploader = StubUploader(.failure(.invalidRequest(reason: "bad")))
        let vm = makeViewModel(uploader: uploader)
        vm.select(data: sampleData, fileName: nil)

        vm.upload()
        await settle(vm)
        #expect(vm.canRetry == false)
        #expect(await uploader.callCount == 1)

        vm.retry()   // guarded
        await settle(vm)
        #expect(await uploader.callCount == 1)
    }

    @Test("Session resolution failure fails non-retryably without a network call")
    func sessionFailure() async {
        let uploader = StubUploader(.success(sampleResponse))
        let vm = makeViewModel(uploader: uploader, sessionIdProvider: { throw TestError() })
        vm.select(data: sampleData, fileName: nil)

        vm.upload()
        await settle(vm)

        #expect(vm.canRetry == false)
        #expect(vm.failureReason != nil)
        #expect(await uploader.callCount == 0)
    }

    @Test("clearSelection() resets to a clean slate after a successful upload")
    func clearAfterSuccess() async {
        let vm = makeViewModel(uploader: StubUploader(.success(sampleResponse)))
        vm.select(data: sampleData, fileName: nil)
        vm.upload()
        await settle(vm)
        #expect(vm.uploadedResponse != nil)

        vm.clearSelection()
        #expect(vm.selectedImageData == nil)
        #expect(vm.selectedFileName == nil)
        #expect(vm.phase == .idle)
        #expect(vm.canUpload == false)
    }

    @Test("handleSelectionFailure surfaces a non-retryable error and clears selection")
    func selectionFailure() {
        let vm = makeViewModel(uploader: StubUploader(.success(sampleResponse)))
        vm.select(data: sampleData, fileName: nil)
        #expect(vm.canUpload == true)

        vm.handleSelectionFailure()
        #expect(vm.selectedImageData == nil)
        #expect(vm.canUpload == false)
        #expect(vm.canRetry == false)
        #expect(vm.failureReason != nil)
    }
}
