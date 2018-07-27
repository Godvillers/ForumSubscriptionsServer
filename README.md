Godville Forum Subscriptions Server
===================================

The building process is similiar to one described [here][gvrepsrv]. To cut a long story short,

```sh
dub upgrade
dub build -brelease-nobounds

./gvsubsrv -p8000 --verbose
```

[gvrepsrv]: https://github.com/Godvillers/ReporterServer
