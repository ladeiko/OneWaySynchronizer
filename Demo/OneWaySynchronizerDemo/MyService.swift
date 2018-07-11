//
//  MyService.swift
//  OneWaySynchronizerDemo
//
//  Created by Siarhei Ladzeika on 7/10/18.
//  Copyright © 2018 Siarhei Ladzeika. All rights reserved.
//

import Foundation
import UIKit
import Alamofire
import OneWaySynchronizer

typealias Completion = (_ error: Error?) -> Void
typealias PreviewCompletion = (_ error: Error?, _ image: UIImage?) -> Void

fileprivate struct RemoteItemDescription: OneWaySynchronizerItemDescription {
    var owsPrimaryKey: OneWaySynchronizerItemKey
    var owsDownloadOrder: OneWaySynchronizerItemDownloadOrder
    var order: Int
    var title: String
    var url: String
}

fileprivate class Item: Comparable {
    
    static func < (lhs: Item, rhs: Item) -> Bool {
        return lhs.order < rhs.order
    }
    
    static func == (lhs: Item, rhs: Item) -> Bool {
        return lhs.order == rhs.order
    }
    
    var order: Int
    var key: String
    var title: String
    var previewUrl: URL
    var ready = false
    
    init(key: String, order: Int, title: String, preview: Data) {
        self.key = key
        self.order = order
        self.title = title
        let dir = URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first!).appendingPathComponent("Items").appendingPathComponent(key)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        self.previewUrl = dir.appendingPathComponent("preview.png")
        try! preview.write(to: self.previewUrl)
    }
    
    deinit {
        try? FileManager.default.removeItem(at: previewUrl)
    }
}

class MyService: OneWaySynchronizerProcessor {
    
    private var _synchronizer: OneWaySynchronizer!
    private var _items = [Item]()
    
    init() {
        _synchronizer = OneWaySynchronizer(processor: self)
        _synchronizer.concurrency = 10
        _synchronizer.downloadPreview = true
        _synchronizer.downloadContent = true
    }
    
    func sync(_ completion: @escaping Completion) {
        _synchronizer.sync { (errors) in
            completion(errors?.first)
        }
    }
    
    // MARK: OneWaySynchronizerProcessor
    
    func owsSyncBegin(_ completion: @escaping OwsCompletion) {
        
        // NOTE: Method can be called not in main thread!
        
        completion() // Completion can be called from any thread!
    }
    
    func owsSyncEnd(_ completion: @escaping OwsCompletion) {
        
        // NOTE: Method can be called not in main thread!
        
        DispatchQueue.main.async {
            
            self._items.sort()
            
            completion() // Completion can be called from any thread!
        }
    }
    
    func owsFetchSourceList(_ completion: @escaping OwsItemsCompletion) {
        
        // NOTE: Method can be called not in main thread!
        
        Alamofire.request("https://api.github.com/users/hadley/orgs").responseJSON { response in
            
            var items = [RemoteItemDescription]()
            
            if let json = response.result.value {
                for (i, item) in (json as! [Dictionary<String,Any>]).enumerated() {
                    items.append(RemoteItemDescription(owsPrimaryKey: String(item["id"] as! Int),
                                                       owsDownloadOrder: 0,
                                                       order: i,
                                                       title: item["login"] as! String,
                                                       url: item["avatar_url"] as! String))
                }
            }
            
            completion(nil, items)
        }
    }
    
    func owsGetLocalKeys(_ completion: @escaping OwsKeysCompletion) {
        
        // NOTE: Method can be called not in main thread!
        
        DispatchQueue.main.async {
            completion(nil, self._items.map({$0.key})) // No matter what thread is now running on!
        }
            
    }
    
    func owsRemoveLocalItems(for primaryKeys: Set<OneWaySynchronizerItemKey>, completion: @escaping OwsSimpleCompletion) {
        
        // NOTE: Method can be called not in main thread!
        
        DispatchQueue.main.async {
            self._items = self._items.filter({ !primaryKeys.contains($0.key) })
        
            completion(nil) // No matter what thread is now running on!
        }
    }
    
    func owsShouldUpdateItem(forKey: OneWaySynchronizerItemKey, with description: OneWaySynchronizerItemDescription, completion: @escaping OwsBoolCompletion) {
        
        // NOTE: Method can be called not in main thread!
        
        completion(nil, true) // No matter what thread is now running on!
    }
    
    func owsDownloadItemPreview(forDescription description: OneWaySynchronizerItemDescription, completion: @escaping OwsSimpleCompletion) {
        
        // NOTE: Method can be called not in main thread!
        
        let description = description as! RemoteItemDescription
        
        DispatchQueue.global(qos: .background).async {
            
            let data = (try! NSData(contentsOf: URL(string: description.url)!) as Data)
            
            DispatchQueue.main.async {
                
                if let index = self._items.index(where: { (item) -> Bool in description.owsPrimaryKey == item.key }) {
                    try! data.write(to: self._items[index].previewUrl)
                }
                else {
                    let item = Item(key: description.owsPrimaryKey, order: description.order, title: description.title, preview: data)
                    self._items.append(item)
                }
                
                completion(nil) // No matter what thread is now running on!
            }
        }
        
    }
    
    func owsDownloadItem(forDescription description: OneWaySynchronizerItemDescription, completion: @escaping OwsSimpleCompletion) {
        
        // NOTE: Method can be called not in main thread!
        
        DispatchQueue.main.async {
            
            let description = description as! RemoteItemDescription
            
            if let index = self._items.index(where: { (item) -> Bool in description.owsPrimaryKey == item.key }) {
                self._items[index].ready = true
            }
            
            completion(nil) // No matter what thread is now running on!
        }

    }
    
    func owsPrepareDownload(of descriptions: [OneWaySynchronizerItemDescription], completion: @escaping OwsItemsCompletion) {
        completion(nil, descriptions)
    }
    
    // MARK: Public
    
    func count() -> Int {
        return _items.count
    }
    
    func key(at index: Int) -> String {
        return _items[index].key
    }
    
    func title(at index: Int) -> String {
        return _items[index].ready ? _items[index].title : "loading"
    }
    
    func preview(at index: Int, completion: @escaping PreviewCompletion) {
        let path = _items[index].previewUrl.path
        DispatchQueue.global(qos: .userInteractive).async {
            let image = UIImage(contentsOfFile: path)
            assert(image != nil)
            DispatchQueue.main.async {
                completion(nil, image)
            }
        }
    }
    
}
