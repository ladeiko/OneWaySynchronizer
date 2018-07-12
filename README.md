[![Build Status](https://travis-ci.org/ladeiko/OneWaySynchronizer.svg?branch=master)](https://travis-ci.org/ladeiko/OneWaySynchronizer)

# Purpose

The simplest abstraction to synchronize local data with remote source. For iOS, written in swift.

## Overview

Many applications uses remote servers as sources for some data rendered later to user. Synchronization process is used to fetch data from remote server  and store them locally. This operation consists of some standard stages: fetch, compare, diff, download new, etc... This module was created to simplify synchronization process by implementing all logic inside with interaction via protocol with external 'so-called' processor. All you need, just implement all requied async methods. All items should be unique and must have string unique keys. Synchronizer does not define order of items, it is responsibility of programmer. Demo example, fills order from server response and then sort items according to it.

## Installation

### Cocoapods

```ruby
pod "OneWaySynchronizer"
```

### Manually

Clone repository and add files from ```Source``` folder to project.

## Usage

For detailed example see [Demo](Demo) folder.

## OneWaySynchronizer

### Syncrhonization flow

```
   sync()
      ↓
   post OneWaySynchronizerDidChangeSyncStatusNotification
      ↓
   [called at the beginning of synchronization process]
   owsSyncBegin
      ↓
   [return list of items from remote source, for example, from server]
   owsFetchSourceList
      ↓       ↓
  ┌─< err     ok
  │           ↓
  │ [return unique keys of locally existing items]
  │  owsGetLocalKeys 
  │   ↓       ↓
  ├─< err     ok
  │           ↓
  │ [remove local items, because their keys were not found in source list]
  │  owsRemoveLocalItems 
  │   ↓       ↓
  ├─< err     ok
  │           ↓
  │ [define if synchronizer should update already existing item]
  │  owsShouldUpdateItem 
  │   ↓       ↓
  ├─< err     ok
  │           ↓
  │ [here you can reorder, filter items for next download operations]
  │  owsPrepareDownload 
  │   ↓       ↓ 
  ├─< err     ok
  │           ↓
  │ [download preview of item if necessary]
  │  owsDownloadItemPreview <───────────────────────────┐
  │   ↓       ↓                                         │
  ├─< err     ok >── concurrent loop for all previews ──┘
  │           ↓
  │ [download main content of item if necessary]
  │  owsDownloadItem <─────────────────────────────────┐
  │   ↓       ↓                                        │
  ├─< err     ok >── concurrent loop for all previews ─┘
  │           ↓
  │  [called after synchronization process]
  └> owsSyncEnd 
      ↓
   sync completions
      ↓ 
   post OneWaySynchronizerDidChangeSyncStatusNotification

```

### Methods

* ```func sync(completion: @escaping OwsSyncCompletion = { _ in })```

Starts synchronization process. If another process is in progress, then after its completion new synchronization will be initiated, both completion callbacks will be called at the end of the last synchronization.

* ```func cancel()``` 

Cancels currently running synchonization. If no any synchronization is running, then does nothing.

### Options
* ```concurrency``` - number of concurrent tasks while downloading. 0 - means auto. Default is 0.
* ```downloadPreview``` - if true, then synchonizer should call method for preview downloading. Default is false.
* ```downloadContent``` - if true, then synchonizer should call method for content downloading. Default is true.
* ```stopOnError``` - if true, then sync will stop as soon as possible after first error. Default is true.

## Changes

See [CHANGELOG](CHANGELOG.md)

## License

MIT. See [LICENSE](LICENSE)

## Author

Siarhei Ladzeika <sergey.ladeiko@gmail.com>

