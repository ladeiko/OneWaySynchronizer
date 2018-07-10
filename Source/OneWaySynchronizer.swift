//
//  OneWaySynchronizer.swift
//  OneWaySynchronizerDemo
//
//  Created by Siarhei Ladzeika on 7/7/18.
//  Copyright © 2018 Siarhei Ladzeika. All rights reserved.
//

import Foundation

public typealias OneWaySynchronizerItemKey = String
public typealias OwsCompletion = () -> Void
public typealias OwsSimpleCompletion = (_ error: Error?) -> Void
public typealias OwsKeysCompletion = (_ error: Error?, _ keys: [OneWaySynchronizerItemKey]) -> Void
public typealias OwsItemsCompletion = (_ error: Error?, _ items: Array<OneWaySynchronizerItemDescription>?) -> Void
public typealias OwsBoolCompletion = (_ error: Error?, _ value: Bool?) -> Void

public enum OwsError: Error {
    case fetchError(underlyingError: Error)
    case diffError(underlyingError: Error)
    case removeError(underlyingError: Error)
    case shouldUpdateError(key: OneWaySynchronizerItemKey, underlyingError: Error)
    case downloadPreviewError(key: OneWaySynchronizerItemKey, underlyingError: Error)
    case downloadContentError(key: OneWaySynchronizerItemKey, underlyingError: Error)
}

public typealias OwsSyncCompletion = (_ errors: [OwsError]?) -> Void

public protocol OneWaySynchronizerItemDescription {
    var owsPrimaryKey: OneWaySynchronizerItemKey { get }
}

public protocol OneWaySynchronizerProcessor {
    
    /**
     Notifies that synchronization just begin.
     */
    func owsSyncBegin(_ completion: @escaping OwsCompletion)
    
    /**
     Notifies that synchronization just complete.
     */
    func owsSyncEnd(_ completion: @escaping OwsCompletion)
    
    /**
     It is used to get source list of items. List of local items is sycnrhonized with this list.
     For example, if some item exists in local list, but does not exist in source list, then it will be deleted
     during synchronization process.
     For usage see examples.
     */
    func owsFetchSourceList(_ completion: @escaping OwsItemsCompletion) -> Void
    
    /**
     Get list of keys of local items. This list is compared with source list.
     For usage see examples.
     */
    func owsGetLocalKeys(_ completion: @escaping OwsKeysCompletion)
    
    /**
     Should remove items from local list identified by passed keys.
     For usage see examples.
     */
    func owsRemoveLocalItems(for primaryKeys: Set<OneWaySynchronizerItemKey>, completion: @escaping OwsSimpleCompletion)
    
    /**
     Method additional asks if some already existing items should be updated.
     For example, you can check modification date of local item and remote one
     and decide to update item.
     For usage see examples.
     */
    func owsShouldUpdateItem(forKey: OneWaySynchronizerItemKey, with description: OneWaySynchronizerItemDescription, completion: @escaping OwsBoolCompletion)
    
    /**
     Should download preview for item (if required), for example, thumbnail, etc...
     For usage see examples.
     */
    func owsDownloadItemPreview(forDescription description: OneWaySynchronizerItemDescription, completion: @escaping OwsSimpleCompletion)
    
    /**
     Should download main content of item.
     For usage see examples.
     */
    func owsDownloadItem(forDescription description: OneWaySynchronizerItemDescription, completion: @escaping OwsSimpleCompletion)
}

extension Notification.Name {
    /**
     It is broadcasted when syncing status of OneWaySynchronizer was changed.
     It is guaranteed that it will be sent in main thread context.
    */
    public static let OneWaySynchronizerDidChangeSyncStatusNotification = Notification.Name("OneWaySynchronizerDidChangeSyncStatusNotification")
}

open class OneWaySynchronizer {
    
    // MARK: Private vars
    
    private var _syncing = false {
        didSet {
            if _syncing {
                if _queue == nil {
                    _queue = DispatchQueue(label: "vss-\(Unmanaged.passUnretained(self).toOpaque())")
                }
            }
            else {
               _queue = nil
            }
        }
    }
    
    private var _needsResync = false
    private var _processor: OneWaySynchronizerProcessor
    private var _completions = [OwsSyncCompletion]()
    private var _queue: DispatchQueue!
    private var _downloadPreview = false
    private var _downloadContent = true
    private var _concurrency: Int = 0
    private var _stopOnError = true
    
    private typealias Completion = () -> Void
    
    private class SyncContext {
        
        var keyedItems = [OneWaySynchronizerItemKey: OneWaySynchronizerItemDescription]()
        var items = [OneWaySynchronizerItemDescription]()
        var toRemove = Set<OneWaySynchronizerItemKey>()
        var toDownloadPreviews = [OneWaySynchronizerItemDescription]()
        var toDownloadItems = [OneWaySynchronizerItemDescription]()
        var toUpdate = Set<OneWaySynchronizerItemKey>()
        var concurrency: Int = 0
        var downloadPreview = false
        var downloadContent = true
        var stopOnError = true
        var concurrencyLimit: Int = 0
        var errors = [OwsError]()
        
        init(){}
    }
    
    // MARK: Life cycle
    
    public init(processor: OneWaySynchronizerProcessor) {
        _processor = processor
    }
    
    // MARK: Public properties

    /**
     Returns current syncing status of object.
     Getter is thread-safe.
     */
    open var isSyncing: Bool {
        return mainGet({ () -> Bool in
            return _syncing
        })
    }
    
    /**
     Defines how many concurrent download operations will be used.
     Minimum allowed value is 0. Default value is 1. If value is 0, then
     concurrency is defined by CPU count.
     Setter and getter is thread-safe.
    */
    open var concurrency: Int {
        set {
            mainSet(newValue < 0 ? 0 : newValue) { (value) in
                _concurrency = value
            }
        }
        get {
            return mainGet({ () -> Int in
                return _concurrency
            })
        }
    }
    
    /**
     Defines if service should try to download items preview.
     Default value is false. Setter and getter is thread-safe.
     */
    open var downloadPreview: Bool {
        set {
            mainSet(newValue) { (value) in
                _downloadPreview = value
            }
        }
        get {
            return mainGet({ () -> Bool in
                return _downloadPreview
            })
        }
    }
    
    /**
     Defines if service should try to download items content.
     Default value is true. Setter and getter is thread-safe.
     */
    open var downloadContent: Bool {
        set {
            mainSet(newValue) { (value) in
                _downloadContent = value
            }
        }
        get {
            return mainGet({ () -> Bool in
                return _downloadContent
            })
        }
    }
    
    /**
     Defines behavior when error occurred while downloading of some item content or preview.
     Default value is true. If true, then service will stop syncing as soon as possible after first error occurred.
     */
    open var stopOnError: Bool {
        set {
            mainSet(newValue) { (value) in
                _stopOnError = value
            }
        }
        get {
            return mainGet({ () -> Bool in
                return _stopOnError
            })
        }
    }
    
    // MARK: Public methods
    
    /**
     Starts synchronization process. If another sync is in progress, then this call will be queued for later
     execution after currently running one completes. Method is thread-safe.
     */
    open func sync(completion: @escaping OwsSyncCompletion = { _ in }) {
        
        DispatchQueue.main.async {
            
            self._completions.append(completion)
            
            guard self._syncing == false else {
                self._needsResync = true
                return
            }
            
            self._syncing = true

            let context = SyncContext()
            
            context.concurrencyLimit = self.concurrency == 0 ? ProcessInfo.processInfo.processorCount : self.concurrency
            context.downloadPreview = self.downloadPreview
            context.downloadContent = self.downloadContent
            context.stopOnError = self.stopOnError
            
            let statusNotification: Notification.Name = .OneWaySynchronizerDidChangeSyncStatusNotification
            NotificationCenter.default.post(name: statusNotification, object: self, userInfo: nil)
            
            DispatchQueue.global(qos: .background).async {
                
                self._processor.owsSyncBegin {
            
                    DispatchQueue.global(qos: .background).async {
                        
                        self.fetch(with: context) {
                            
                            DispatchQueue.main.async {
                                
                                self._syncing = false
                            
                                if self._needsResync {
                                    self._needsResync = false
                                    self.sync(completion: { (_) in })
                                    return
                                }
                                
                                self._processor.owsSyncEnd {
                                    
                                    DispatchQueue.main.async {
                                    
                                        let completions = self._completions
                                        self._completions.removeAll()
                                        
                                        for completion in completions {
                                            completion(context.errors.count != 0 ? context.errors : nil)
                                        }
                                        
                                        NotificationCenter.default.post(name: statusNotification, object: self, userInfo: nil)
                                        
                                    }
                                    
                                }

                            }
                            
                        }
                        
                    }
                    
                }
                
            }
        }
        
    }
    
    // MARK: Helpers
    
    private func mainGet<T>(_ block: () -> T ) -> T {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        return block()
    }
    
    private func mainSet<T>(_ value: T, _ block: (_ v: T) -> Void ) {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        block(value)
    }
    
    private func fetch(with context: SyncContext, _ completion: @escaping Completion) {
        
        _processor.owsFetchSourceList { error, items in
            
            DispatchQueue.global(qos: .background).async {
                
                if let error = error {
                    context.errors.append(OwsError.fetchError(underlyingError: error))
                    completion()
                    return
                }
            
                context.items = items!
                context.keyedItems = context.items.reduce(into: [OneWaySynchronizerItemKey: OneWaySynchronizerItemDescription](), { (result, item) in
                    result[item.owsPrimaryKey] = item
                })
                
                self.diff(with: context, completion)
                
            }
        }
    }
    
    private func diff(with context: SyncContext, _ completion: @escaping Completion) {
        
        let newKeys = context.items.map({ $0.owsPrimaryKey }).sorted()

        self._processor.owsGetLocalKeys({ (error, existingKeys) in
            
            DispatchQueue.global(qos: .background).async {
                
                if let error = error {
                    context.errors.append(OwsError.diffError(underlyingError: error))
                    completion()
                    return
                }
                
                context.toRemove = Set(existingKeys)
                
                for new in newKeys {
                    if context.toRemove.remove(new) != nil {
                        context.toUpdate.insert(new)
                    }
                    else {
                        context.toDownloadItems.append(context.keyedItems[new]!)
                    }
                }
                
                self.remove(with: context, completion)
            }
        })
        
    }
    
    private func remove(with context: SyncContext, _ completion: @escaping Completion) {
        if context.toRemove.count != 0 {
            
            self._processor.owsRemoveLocalItems(for: context.toRemove, completion: { (error) in
                
                DispatchQueue.global(qos: .background).async {
                    
                    if let error = error {
                        context.errors.append(OwsError.removeError(underlyingError: error))
                        completion()
                        return
                    }
                    
                    self.update(with: context, completion)
                }
            })
        }
        else {
            self.update(with: context, completion)
        }
    }
    
    private func update(with context: SyncContext, _ completion: @escaping Completion) {
        
        if context.toUpdate.count != 0 {
            
            let key = context.toUpdate.popFirst()!
            
            self._processor.owsShouldUpdateItem(forKey: key, with: context.keyedItems[key]!) { (error, ok) in
                
                DispatchQueue.global(qos: .background).async {
                    
                    if let error = error {
                        context.errors.append(OwsError.shouldUpdateError(key: key, underlyingError: error))
                        completion()
                        return
                    }
                    
                    if ok! {
                        context.toDownloadItems.append(context.keyedItems[key]!)
                    }
                    
                    self.update(with: context, completion)
                    
                }
            }
        }
        else {
            
            if context.downloadPreview {
                context.toDownloadPreviews = context.toDownloadItems
            }
            
            if context.downloadContent == false {
                context.toDownloadItems.removeAll()
            }
            
            self.preview(with: context, completion)
        }
    }
    
    private func preview(with context: SyncContext, _ completion: @escaping Completion) {
        
        _queue.async {
            
            while (context.toDownloadPreviews.count != 0)
                && (context.concurrency < context.concurrencyLimit)
                && (context.stopOnError == false || context.errors.count == 0) {
                
                let description = context.toDownloadPreviews.remove(at: 0)
                
                context.concurrency += 1
                
                DispatchQueue.global(qos: .background).async {
                    
                    self._processor.owsDownloadItemPreview(forDescription: description) { error in
                        
                        self._queue.async {
                            
                            context.concurrency -= 1
                            
                            if let error = error {
                                context.errors.append(OwsError.downloadPreviewError(key: description.owsPrimaryKey, underlyingError: error))
                            }
                            
                            self.preview(with: context, completion)
                        }
                    }
                    
                }
                
            }
            
            if context.concurrency == 0 {
                self.download(with: context, completion)
            }
            
        }
    }
    
    private func download(with context: SyncContext, _ completion: @escaping Completion) {

        _queue.async {
            
            while (context.toDownloadItems.count != 0)
                && (context.concurrency < context.concurrencyLimit)
                && (context.stopOnError == false || context.errors.count == 0) {
                
                let description = context.toDownloadItems.remove(at: 0)
                
                context.concurrency += 1
                
                DispatchQueue.global(qos: .background).async {
                    
                    self._processor.owsDownloadItem(forDescription: description) { error in
                        
                        self._queue.async {
                            
                            context.concurrency -= 1
                    
                            if let error = error {
                                context.errors.append(OwsError.downloadContentError(key: description.owsPrimaryKey, underlyingError: error))
                            }
                            
                            self.download(with: context, completion)
                        }
                    }
                    
                }
                
            }
            
            if context.concurrency == 0 {
                completion()
            }
            
        }
    }
}
