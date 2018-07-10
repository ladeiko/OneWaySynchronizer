# OneWaySynchronizer

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

## Options
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

