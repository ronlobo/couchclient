//Copyright (C) 2013 Potix Corporation. All Rights Reserved.
//History: Wed, Mar 04, 2013  05:31:09 PM
// Author: hernichen

part of rikulo_memcached;

class ConfigProvider {
  static const String DEFAULT_POOL_NAME = 'default';
  static const String ANONYMOUS_AUTH_BUCKET = 'default';

  static const String CLIENT_SPEC_VER = '1.0';

  List<Uri> baseList;
  String restUsr;
  String restPwd;
  Uri loadedBaseUri;
  Map<String, Bucket> buckets = new HashMap(); //bucketname -> Bucket
  ConfigParserJson configParser = new ConfigParserJson();
//  Map<String, BucketMonitor> monitors = new HashMap();
//  String reSubBucket;
//  Reconfigurable reSubRec;

  ConfigProvider(List<Uri> baseList, [String user, String pass])
        : this.baseList = baseList,
          restUsr = user,
          restPwd = pass;

  Future<Bucket> getBucketConfig(String bucketname) {
    if (bucketname == null || bucketname.trim().isEmpty)
      throw new ArgumentError("Bucket name can not be blank.");
    Bucket bucket = buckets[bucketname];
    if (bucket == null) {
      return _readPools(bucketname);
    } else {
      return new Future.immediate(bucket);
    }
  }

  Future<List<SocketAddress>> getServerList(String bucketname) {
    Future<Bucket> f = getBucketConfig(bucketname);
    return f.then((Bucket bucket)
        => HttpUtil.parseSocketAddresses(bucket.config.servers.join(' ')));
  }

  Future<Config> getLastestConfig(String bucketname) {
    Future<Bucket> f = getBucketConfig(bucketname);
    return f.then((Bucket bucket) => bucket.config);
  }

  String getAnonymousAuthBucket()
  => ANONYMOUS_AUTH_BUCKET;

//  void finishResubscribe() {
//    monitors.clear();
//    subscribe(reSubBucket, reSubRec);
//  }
//
//  void markForResubscribe(String bucketname, Reconfigurable rec) {
//    reSubBucket = bucketname;
//    reSubRec = rec;
//  }
//
//  /**
//   * Subscribe for config updates
//   */
//  void subscribe(String bucketname, Reconfigurable rec) {
//    if (null == bucketname || (null != reSubBucket
//      && bucketname != reSubBucket)) {
//      throw new ArgumentError("Bucket name cannot be null and must"
//        " never be re-set to a new object.");
//    }
//    if (null == rec || (null != reSubRec && rec != reSubRec)) {
//      throw new ArgumentError("Reconfigurable cannot be null and"
//        " must never be re-set to a new object");
//    }
//    reSubBucket = bucketname;  // More than one subscriber, would be an error
//    reSubRec = rec;
//    Future<Bucket> f = getBucketConfig(bucketname);
//
//    f.then((bucket) {
//      ReconfigurableObserver obs = new ReconfigurableObserver(rec);
//      BucketMonitor monitor = this.monitors[bucketname];
//      if (monitor == null) {
//        Uri streamingUri = bucket.streamingUri;
//        monitor = new BucketMonitor(this.loadedBaseUri.resolveUri(streamingUri),
//          bucketname, this.restUsr, this.restPwd, configParser);
//        this.monitors[bucketname] = monitor;
//        monitor.addObserver(obs);
//        monitor.startMonitor();
//      } else {
//        monitor.addObserver(obs);
//      }
//    });
//  }
//
//  /**
//   * Unsubscribe from updates on a given bucket and reconfigurable.
//   */
//  void unsubscribe(String bucketname, Reconfigurable rec) {
//    BucketMonitor monitor = this.monitors[bucketname];
//    if (monitor != null) {
//      monitor.deleteObserver(new ReconfigurableObserver(rec));
//    }
//  }
//
//  /**
//   * Shutdowns a monitor connections to the REST service.
//   */
//  void shutdown() {
//    for (BucketMonitor monitor in monitors.values)
//      monitor.shutdown();
//  }

  /**
   * Give a bucketname, walk the baseList until found the needed bucket.
   */
  Future<Bucket> _readPools(String bucketname) {
    Completer<Bucket> cmpl = new Completer();
    _readPools0(bucketname, cmpl, 0);
    return cmpl.future;
  }

  void _readPools0(String bucketname, Completer<Bucket> cmpl, int idx) {
    if (idx >= baseList.length) //none found
      cmpl.complete(null);

    Uri baseUri = baseList[idx];
    _readUri(null, baseUri, restUsr, restPwd)
      .then((base) {
        if (base.trim().isEmpty)
          return _readPools0(bucketname, cmpl, idx+1); //check next Pool
        Map<String, Pool> poolMap = configParser.parseBase(base);
        if (!poolMap.containsKey(DEFAULT_POOL_NAME))
          return _readPools0(bucketname, cmpl, idx+1); //check next Pool

        //Load basic information for each Pool
        List<Future<Pool>> poolfs = new List();
        for (Pool pool in poolMap.values) {
          Future<String> fpoolstr = _readUri(baseUri, pool.uri, restUsr, restPwd);
          Future<Pool> fpool = fpoolstr.then((poolstr) {
            print("poolstr:-------->[$poolstr]");
            configParser.loadPool(pool, poolstr);
            return pool;
          });
          poolfs.add(fpool);
        }

        //Load Buckets information for each Pool
        //  after all pools loaded basic information
        Future<List<Pool>> doneLoadBasic = Future.wait(poolfs);
        doneLoadBasic.then((List<Pool> pools) {
          List<Future<Pool>> bucketsfs = new List();
          for (Pool pool in pools) {
            print("pool.bucketsUri---->[${pool.bucketsUri}]");
            Future<String> fbucketsStr = _readUri(baseUri, pool.bucketsUri, restUsr, restPwd);
            Future<Pool> fpool = fbucketsStr.then((bucketsStr) {
              Map<String, Bucket> bucketsForPool =
                  configParser.parseBuckets(bucketsStr);
              pool.replaceBuckets(bucketsForPool);
              return pool;
            });
            bucketsfs.add(fpool);
          }

          //check if found the named bucket among this set of pools
          //  after all pools loaded Buckets information
          Future<List<Pool>> doneLoadBuckets = Future.wait(bucketsfs);
          doneLoadBuckets.then((List<Pool> pools) {
            bool bucketFound = false;
            for (Pool pool in pools) {
              if (pool.hasBucket(bucketname)) {
                bucketFound = true;
                break;
              }
            }
            //found the bucket, cache in the ConfigProvider
            if (bucketFound) {
              for (Pool pool in pools) {
                Map robuckets = new HashMap.from(pool.currentBuckets);
                for (String key in robuckets.keys) {
                  buckets[key] = robuckets[key];
                }
              }
              this.loadedBaseUri = baseUri;
              cmpl.complete(buckets[bucketname]); //found the bucket, break out recursive loop
            } else
              return _readPools0(bucketname, cmpl, idx+1); //check next Pool
          });
        });
      });
  }

  Future<String> _readUri(Uri base, Uri resource, String usr, String pass) {
    Map<String, String> headers = new LinkedHashMap();
    headers[HttpHeaders.ACCEPT] = "application/json";
    headers[HttpHeaders.USER_AGENT] = "Couchbase Dart Client";
    headers["X-memcachekv-Store-Client-Specification-Version"] = CLIENT_SPEC_VER;
    HttpClient client = new HttpClient();
    try {
      return HttpUtil.uriGet(client, base, resource, usr, pass, headers);
    } finally {
      client.close();
    }
  }
}

