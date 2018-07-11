//
//  OneWaySynchronizerDemoTests.swift
//  OneWaySynchronizerDemoTests
//
//  Created by Siarhei Ladzeika on 7/7/18.
//  Copyright © 2018 Siarhei Ladzeika. All rights reserved.
//

import XCTest
import OneWaySynchronizer

@testable import OneWaySynchronizerDemo

enum TestError: Error {
    case error1
    case error2
    case error3
}

func isFetchError(_ err: Error?, underlying: Error) -> Bool {
    guard let err = err as? OwsError else {
        return false
    }
    
    switch err {
    case let .fetchError(underlyingError):
        return underlyingError.localizedDescription == underlying.localizedDescription
    default:
        return false
    }
}

func isDownloadContentError(_ err: Error?, key: OneWaySynchronizerItemKey, underlying: Error) -> Bool {
    guard let err = err as? OwsError else {
        return false
    }
    
    switch err {
    case let .downloadContentError(_key, underlyingError):
        return _key == key && underlyingError.localizedDescription == underlying.localizedDescription
    default:
        return false
    }
}

func isCancelError(_ err: Error?) -> Bool {
    guard let err = err as? OwsError else {
        return false
    }
    switch err {
    case .cancelledError:
        return true
    default:
        return false
    }
}

class TestItem: OneWaySynchronizerItemDescription {
    
    func vss_shouldBeUpdated(with remoteItem: TestItem) -> Bool {
        return false
    }
    
    typealias K = String
    
    var owsPrimaryKey: OneWaySynchronizerItemKey
    var owsDownloadOrder: OneWaySynchronizerItemDownloadOrder
    let downloadError: Error?
    
    init(key: String, order: Int, downloadError: Error? = nil ) {
        owsPrimaryKey = key
        owsDownloadOrder = order
        self.downloadError = downloadError
    }
    
    init(key: String, downloadError: Error? = nil ) {
        owsPrimaryKey = key
        owsDownloadOrder = 0
        self.downloadError = downloadError
    }
}

class TestProcessor: OneWaySynchronizerProcessor {
    
    typealias S = TestItem
    typealias K = TestItem.K
    
    let fetchList: [TestItem]
    
    var beginCalled = 0
    var endCalled = 0
    var shouldBeUpdated = Set<String>()
    var downloadedPreview = Set<String>()
    var downloaded = Set<String>()
    var downloadedOrder = [String]()
    var downloadedPreviewOrder = [String]()
    var removed = Set<String>()
    
    var existingKeys = Array<K>()
    
    var fetchError: Error?
    
    init(fetchList: [TestItem]) {
        self.fetchList = fetchList
    }
    
    var removeItemsCalled = 0
    var shouldBeUpdatedCalled = 0
    
    // MARK: OneWaySynchronizerProcessor
    
    func owsSyncBegin(_ completion: @escaping OwsCompletion) {
        beginCalled += 1
        completion()
    }
    
    func owsSyncEnd(_ completion: @escaping OwsCompletion) {
        endCalled += 1
        completion()
    }

    func owsFetchSourceList(_ completion: @escaping OwsItemsCompletion) -> Void {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        completion(fetchError, fetchError != nil ? nil : fetchList)
    }
    
    func owsGetLocalKeys(_ completion: @escaping (Error?, [K]) -> Void) {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        let copy = Array<K>(existingKeys)
        DispatchQueue.main.async {
            completion(nil, copy)
        }
    }
    
    func owsRemoveLocalItems(for primaryKeys: Set<K>, completion: @escaping OwsSimpleCompletion) {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        removeItemsCalled += primaryKeys.count
        for k in primaryKeys { removed.insert(k) }
        existingKeys = existingKeys.filter({ !primaryKeys.contains($0) })
        DispatchQueue.main.async {
            completion(nil)
        }
    }
    
    func owsShouldUpdateItem(forKey: OneWaySynchronizerItemKey, with description: OneWaySynchronizerItemDescription, completion: @escaping OwsBoolCompletion) {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        shouldBeUpdatedCalled += 1
        completion(nil, shouldBeUpdated.contains(description.owsPrimaryKey))
    }
    
    func owsDownloadItemPreview(forDescription description: OneWaySynchronizerItemDescription, completion: @escaping OwsSimpleCompletion) {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        downloadedPreview.insert(description.owsPrimaryKey)
        downloadedPreviewOrder.append(description.owsPrimaryKey)
        completion(nil)
    }
    
    func owsDownloadItem(forDescription description: OneWaySynchronizerItemDescription, completion: @escaping OwsSimpleCompletion) {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        downloaded.insert(description.owsPrimaryKey)
        downloadedOrder.append(description.owsPrimaryKey)
        if !existingKeys.contains(description.owsPrimaryKey) {
            existingKeys.append(description.owsPrimaryKey)
        }
        completion((description as! TestItem).downloadError)
    }
    
    func owsPrepareDownload(of descriptions: [OneWaySynchronizerItemDescription], completion: @escaping OwsItemsCompletion) {
        completion(nil, descriptions)
    }

}

class OneWaySynchronizerDemoTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testSuccess() {
        
        let startExpectation = XCTestExpectation(description: "start")
        let endExpectation = XCTestExpectation(description: "start")
        
        let expectation = XCTestExpectation(description: "sync")
        var failed: [Error]?
        let processor = TestProcessor(fetchList:[
            TestItem(key: "A", order: 1),
            TestItem(key: "B", order: 0),
            TestItem(key: "C", order: 2)
            ])
        let service = OneWaySynchronizer(processor: processor)
        service.concurrency = 1
        let localObserver = NotificationCenter.default.addObserver(forName: .OneWaySynchronizerDidChangeSyncStatusNotification, object: service, queue: OperationQueue.main) { (notification) in
            XCTAssert(Thread.isMainThread)
            if (notification.object as! OneWaySynchronizer).isSyncing {
                startExpectation.fulfill()
            }
            else {
                endExpectation.fulfill()
            }
        }
        
        service.sync { (error) in
            failed = error
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10)
        wait(for: [startExpectation, endExpectation], timeout: 10)
        
        NotificationCenter.default.removeObserver(localObserver)
        
        XCTAssert(processor.beginCalled == 1)
        XCTAssert(processor.endCalled == 1)
        XCTAssert(failed == nil)
        XCTAssert(Set(processor.fetchList.map({$0.owsPrimaryKey})) == processor.downloaded)
        XCTAssert(processor.downloadedOrder == ["B", "A", "C"])
        XCTAssert(processor.removeItemsCalled == 0)
        XCTAssert(processor.shouldBeUpdatedCalled == 0)
        XCTAssert(processor.removed.count == 0)
        XCTAssert(processor.downloadedPreview.count == 0)
    }
    
    func testSuccessWithPreview() {
        
        let expectation = XCTestExpectation(description: "sync")
        var failed: [Error]?
        let processor = TestProcessor(fetchList:[
            TestItem(key: "A", order: 1),
            TestItem(key: "B", order: 0),
            TestItem(key: "C", order: 2)
            ])
        let service = OneWaySynchronizer(processor: processor)
        service.concurrency = 1
        service.downloadPreview = true
        service.sync { (error) in
            failed = error
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10)
        XCTAssert(failed == nil)
        XCTAssert(Set(processor.fetchList.map({$0.owsPrimaryKey})) == processor.downloaded)
        XCTAssert(processor.downloadedOrder == ["B", "A", "C"])
        XCTAssert(processor.downloadedPreviewOrder == ["B", "A", "C"])
        XCTAssert(processor.removeItemsCalled == 0)
        XCTAssert(processor.shouldBeUpdatedCalled == 0)
        XCTAssert(processor.removed.count == 0)
        XCTAssert(processor.downloadedPreview == Set(["A", "B", "C"]))
    }
    
    func testSuccessOnlyWithPreview() {
        
        let expectation = XCTestExpectation(description: "sync")
        var failed: [Error]?
        let processor = TestProcessor(fetchList:[
            TestItem(key: "A"),
            TestItem(key: "B")
            ])
        let service = OneWaySynchronizer(processor: processor)
        service.concurrency = 1
        service.downloadPreview = true
        service.downloadContent = false
        service.sync { (error) in
            failed = error
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10)
        XCTAssert(failed == nil)
        XCTAssert(processor.downloaded.count == 0)
        XCTAssert(processor.removeItemsCalled == 0)
        XCTAssert(processor.shouldBeUpdatedCalled == 0)
        XCTAssert(processor.removed.count == 0)
        XCTAssert(processor.downloadedPreview == Set(["A", "B"]))
    }
    
    func testSuccessWithoutPreviewAndContent() {
        
        let expectation = XCTestExpectation(description: "sync")
        var failed: [Error]?
        let processor = TestProcessor(fetchList:[
            TestItem(key: "A"),
            TestItem(key: "B")
            ])
        let service = OneWaySynchronizer(processor: processor)
        service.concurrency = 1
        service.downloadPreview = false
        service.downloadContent = false
        service.sync { (error) in
            failed = error
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10)
        XCTAssert(failed == nil)
        XCTAssert(processor.downloaded.count == 0)
        XCTAssert(processor.removeItemsCalled == 0)
        XCTAssert(processor.shouldBeUpdatedCalled == 0)
        XCTAssert(processor.removed.count == 0)
        XCTAssert(processor.downloadedPreview.count == 0)
    }
    
    func testCancellation() {
        
        let startExpectation = XCTestExpectation(description: "start")
        let endExpectation = XCTestExpectation(description: "start")
        
        let expectation = XCTestExpectation(description: "sync")
        var failed: [Error]?
        let processor = TestProcessor(fetchList:[
            TestItem(key: "A", order: 1),
            TestItem(key: "B", order: 0),
            TestItem(key: "C", order: 2)
            ])
        let service = OneWaySynchronizer(processor: processor)
        service.concurrency = 1
        let localObserver = NotificationCenter.default.addObserver(forName: .OneWaySynchronizerDidChangeSyncStatusNotification, object: service, queue: OperationQueue.main) { (notification) in
            XCTAssert(Thread.isMainThread)
            if (notification.object as! OneWaySynchronizer).isSyncing {
                startExpectation.fulfill()
            }
            else {
                endExpectation.fulfill()
            }
        }
        
        service.sync { (error) in
            failed = error
            expectation.fulfill()
        }
        
        service.cancel() // cancel ASAP
        
        wait(for: [expectation], timeout: 10)
        wait(for: [startExpectation, endExpectation], timeout: 10)
        
        NotificationCenter.default.removeObserver(localObserver)
        
        XCTAssert(processor.beginCalled == 1)
        XCTAssert(processor.endCalled == 1)
        XCTAssert(failed != nil)
        XCTAssert(failed!.count == 1)
        XCTAssert(isCancelError(failed![0]))
        XCTAssert(processor.downloaded.count == 0)
        XCTAssert(processor.downloadedOrder.count == 0)
        XCTAssert(processor.removeItemsCalled == 0)
        XCTAssert(processor.shouldBeUpdatedCalled == 0)
        XCTAssert(processor.removed.count == 0)
        XCTAssert(processor.downloadedPreview.count == 0)
    }
    
    func testFetchFailure() {
        
        let expectation = XCTestExpectation(description: "sync")
        var failed: [Error]?
        let processor = TestProcessor(fetchList:[
            TestItem(key: "A", downloadError: TestError.error1),
            TestItem(key: "B")
            ])
        
        processor.fetchError = TestError.error3
        
        let service = OneWaySynchronizer(processor: processor)
        service.concurrency = 1
        
        service.sync { (error) in
            failed = error
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10)
        XCTAssert(failed != nil)
        XCTAssert(failed!.count == 1)
        XCTAssert(isFetchError(failed![0], underlying: TestError.error3))
        XCTAssert(processor.downloaded.count == 0)
        XCTAssert(processor.downloadedPreview.count == 0)
    }
    
    func testSingleDownloadItemFailure() {
        
        let expectation = XCTestExpectation(description: "sync")
        var failed: [Error]?
        let processor = TestProcessor(fetchList:[
            TestItem(key: "A", downloadError: TestError.error1),
            TestItem(key: "B")
            ])
        let service = OneWaySynchronizer(processor: processor)
        service.concurrency = 1
        service.sync { (error) in
            failed = error
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10)
        XCTAssert(failed != nil)
        XCTAssert(failed!.count == 1)
        XCTAssert(isDownloadContentError(failed![0], key: "A", underlying: TestError.error1))
        XCTAssert(processor.downloaded == Set(["A"]))
        XCTAssert(processor.downloadedPreview.count == 0)
    }
    
    func testDoubleDownloadItemFailureIfNonStopOnError() {
        
        let expectation = XCTestExpectation(description: "sync")
        var failed: [Error]?
        let processor = TestProcessor(fetchList:[
            TestItem(key: "A", downloadError: TestError.error1),
            TestItem(key: "B", downloadError: TestError.error2)
            ])
        let service = OneWaySynchronizer(processor: processor)
        service.concurrency = 1
        service.stopOnError = false
        service.sync { (error) in
            failed = error
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10)
        XCTAssert(failed != nil)
        XCTAssert(failed!.count == 2)
        XCTAssert(isDownloadContentError(failed![0], key: "A", underlying: TestError.error1))
        XCTAssert(isDownloadContentError(failed![1], key: "B", underlying: TestError.error2))
        XCTAssert(Set(processor.fetchList.map({$0.owsPrimaryKey})) == processor.downloaded)
        XCTAssert(processor.downloadedPreview.count == 0)
    }
    
    func testDoubleDownloadItemFailureIfStopOnError() {
        
        let expectation = XCTestExpectation(description: "sync")
        var failed: [Error]?
        let processor = TestProcessor(fetchList:[
            TestItem(key: "A", downloadError: TestError.error1),
            TestItem(key: "B", downloadError: TestError.error2)
            ])
        let service = OneWaySynchronizer(processor: processor)
        service.concurrency = 1
        service.stopOnError = true
        service.sync { (error) in
            failed = error
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10)
        XCTAssert(failed != nil)
        XCTAssert(failed!.count == 1)
        XCTAssert(isDownloadContentError(failed![0], key: "A", underlying: TestError.error1))
        XCTAssert(processor.downloaded == Set(["A"]))
        XCTAssert(processor.downloadedPreview.count == 0)
    }
    
    func testRemove() {
        
        let expectation = XCTestExpectation(description: "sync")
        var failed: [Error]?
        let processor = TestProcessor(fetchList:[
            TestItem(key: "A"),
            TestItem(key: "B")
            ])
        processor.existingKeys = ["C"]
        let service = OneWaySynchronizer(processor: processor)
        service.concurrency = 1
        service.sync { (error) in
            failed = error
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10)
        XCTAssert(failed == nil)
        XCTAssert(Set(processor.fetchList.map({$0.owsPrimaryKey})) == processor.downloaded)
        XCTAssert(processor.existingKeys == ["A", "B"])
        XCTAssert(processor.removeItemsCalled == 1)
        XCTAssert(processor.removed == Set(["C"]))
        XCTAssert(processor.downloadedPreview.count == 0)
    }
    
    func testUpdate() {
        
        let expectation = XCTestExpectation(description: "sync")
        var failed: [Error]?
        let processor = TestProcessor(fetchList:[
            TestItem(key: "A"),
            TestItem(key: "B")
            ])
        processor.existingKeys = ["A"]
        processor.shouldBeUpdated = Set<String>(["A"])
        let service = OneWaySynchronizer(processor: processor)
        service.concurrency = 1
        service.sync { (error) in
            failed = error
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10)
        XCTAssert(failed == nil)
        XCTAssert(Set(processor.fetchList.map({$0.owsPrimaryKey})) == processor.downloaded)
        XCTAssert(processor.existingKeys == ["A", "B"])
        XCTAssert(processor.removeItemsCalled == 0)
        XCTAssert(processor.removed.count == 0)
        XCTAssert(processor.shouldBeUpdatedCalled == 1)
        XCTAssert(processor.downloadedPreview.count == 0)
    }
    
    func testResync() {
        
        let expectation1 = XCTestExpectation(description: "sync1")
        let expectation2 = XCTestExpectation(description: "sync2")
        
        var failed1: [Error]?
        var failed2: [Error]?
        
        let processor = TestProcessor(fetchList:[
            TestItem(key: "A"),
            TestItem(key: "B")
            ])
        let service = OneWaySynchronizer(processor: processor)
        service.concurrency = 1
        service.sync { (error) in
            failed1 = error
            expectation1.fulfill()
        }
        
        service.sync { (error) in
            failed2 = error
            expectation2.fulfill()
        }
        
        wait(for: [expectation1, expectation2], timeout: 10)
        XCTAssert(failed1 == nil)
        XCTAssert(failed2 == nil)
        XCTAssert(Set(processor.fetchList.map({$0.owsPrimaryKey})) == processor.downloaded)
        XCTAssert(processor.existingKeys == ["A", "B"])
        XCTAssert(processor.removeItemsCalled == 0)
        XCTAssert(processor.removed.count == 0)
        XCTAssert(processor.shouldBeUpdatedCalled == 2)
        XCTAssert(processor.downloadedPreview.count == 0)
    }
    
    
    func testConcurrency() {
        for _ in 0..<10 {
            let expectation = XCTestExpectation(description: "sync")
            var failed: [Error]?
            var items = [TestItem]()
            for i in 0..<100 {
                items.append(TestItem(key: String(i)))
            }
            let processor = TestProcessor(fetchList: items)
            let service = OneWaySynchronizer(processor: processor)
            service.concurrency = 0
            XCTAssert(service.concurrency == 0)
            service.concurrency = -1
            XCTAssert(service.concurrency == 0)
            service.concurrency = 10
            XCTAssert(service.concurrency == 10)
            service.sync { (error) in
                failed = error
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 10)
            XCTAssert(failed == nil)
            XCTAssert(Set(processor.fetchList.map({$0.owsPrimaryKey})) == processor.downloaded)
            XCTAssert(processor.existingKeys.count == items.count)
            XCTAssert(processor.removeItemsCalled == 0)
            XCTAssert(processor.removed.count == 0)
            XCTAssert(processor.shouldBeUpdatedCalled == 0)
            XCTAssert(processor.downloadedPreview.count == 0)
        }
    }
    
    /*func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }*/
    
}
