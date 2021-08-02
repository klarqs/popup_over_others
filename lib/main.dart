import 'package:buildcrypto/custom_button.dart';
import 'package:buildcrypto/splash_screen.dart';
import "package:flutter/material.dart";
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import "dart:collection";
import "dart:async";
import "dart:io";
import "package:intl/intl.dart";
import "dart:convert";
import "package:web_socket_channel/io.dart";
import "package:http/http.dart" as http;
import "package:url_launcher/url_launcher.dart";
import "package:path_provider/path_provider.dart";
import "package:local_database/local_database.dart";
import "package:auto_size_text/auto_size_text.dart";
import "dart:math";
import "package:syncfusion_flutter_charts/charts.dart";
import "package:syncfusion_flutter_core/core.dart";
import "image_keys.dart";
// import "key.dart";
import "package:flutter_svg/flutter_svg.dart";

String _api = "https://api.coincap.io/v2/";
HashMap<String, Map<String, dynamic>> _coinData;
HashMap<String, ValueNotifier<num>> _valueNotifiers =
    HashMap<String, ValueNotifier<num>>();
List<String> _savedCoins;
Database _userData;
Map<String, dynamic> _settings;
String _symbol;

LinkedHashSet<String> _supportedCurrencies = LinkedHashSet.from([
  "USD",
  "AUD",
  "BGN",
  "BRL",
  "CAD",
  "CHF",
  "CNY",
  "CZK",
  "DKK",
  "EUR",
  "GBP",
  "HKD",
  "HRK",
  "HUF",
  "IDR",
  "ILS",
  "INR",
  "ISK",
  "JPY",
  "KRW",
  "MXN",
  "MYR",
  "NOK",
  "NZD",
  "PHP",
  "PLN",
  "RON",
  "RUB",
  "SEK",
  "SGD",
  "THB",
  "TRY",
  "ZAR"
]);
Map<String, dynamic> _conversionMap;
num _exchangeRate;

bool _loading = false;

Future<dynamic> _apiGet(String link) async {
  return json.decode((await http.get(Uri.encodeFull("$_api$link"))).body);
}

void _changeCurrency(String currency) {
  var conversionData = _conversionMap[_settings["currency"]];
  _exchangeRate = conversionData["rate"];
  _symbol = conversionData["symbol"];
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // SyncfusionLicense.registerLicense(syncKey);
  _userData = Database((await getApplicationDocumentsDirectory()).path);
  _savedCoins = (await _userData["saved"])?.cast<String>() ?? [];
  _settings = await _userData["settings"];
  if (_settings == null) {
    _settings = {"disableGraphs": true, "currency": "USD"};
    _userData["settings"] = _settings;
  }
  var exchangeData = json
      .decode((await http.get("https://api.coincap.io/v2/rates")).body)["data"];
  _conversionMap = HashMap();
  for (dynamic data in exchangeData) {
    String symbol = data["symbol"];
    if (_supportedCurrencies.contains(symbol)) {
      _conversionMap[symbol] = {
        "symbol": data["currencySymbol"] ?? "",
        "rate": 1 / num.parse(data["rateUsd"])
      };
    }
  }
  _changeCurrency(_settings["currency"]);
  _coinData = HashMap<String, Map<String, Comparable>>();
  runApp(App());
}

class App extends StatefulWidget {
  @override
  _AppState createState() => _AppState();
}

class _AppState extends State<App> {
  @override
  void initState() {
    super.initState();
    setUpData();
  }

  IOWebSocketChannel socket;

  Future<void> setUpData() async {
    _coinData = HashMap<String, Map<String, Comparable>>();
    _loading = true;
    setState(() {});
    var data = (await _apiGet("assets?limit=2000"))["data"];
    data.forEach((e) {
      String id = e["id"];
      _coinData[id] = e.cast<String, Comparable>();
      _valueNotifiers[id] = ValueNotifier(0);
      for (String s in e.keys) {
        if (e[s] == null) {
          e[s] = (s == "changePercent24Hr" ? -1000000 : -1);
        } else if (!["id", "symbol", "name"].contains(s)) {
          e[s] = num.parse(e[s]);
        }
      }
    });
    _loading = false;
    setState(() {});
    socket?.sink?.close();
    socket =
        IOWebSocketChannel.connect("wss://ws.coincap.io/prices?assets=ALL");
    socket.stream.listen((message) {
      Map<String, dynamic> data = json.decode(message);
      data.forEach((s, v) {
        if (_coinData[s] != null) {
          num old = _coinData[s]["priceUsd"];
          _coinData[s]["priceUsd"] = num.parse(v) ?? -1;
          _valueNotifiers[s].value = old;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
        theme: ThemeData(
            brightness: Brightness.dark,
            accentColor: Colors.white,
            scaffoldBackgroundColor: Colors.grey[700],
            fontFamily: GoogleFonts.montserrat().fontFamily),
        debugShowCheckedModeBanner: false,
        home: SplashScreen());
  }
}

String sortingBy;

class ListPage extends StatefulWidget {
  final bool savedPage;

  ListPage(this.savedPage) : super(key: ValueKey(savedPage));

  @override
  _ListPageState createState() => _ListPageState();
}

typedef SortType(String s1, String s2);

SortType sortBy(String s) {
  String sortVal = s.substring(0, s.length - 1);
  bool ascending = s.substring(s.length - 1).toLowerCase() == "a";
  return (s1, s2) {
    if (s == "custom") {
      return _savedCoins.indexOf(s1) - _savedCoins.indexOf(s2);
    }
    Map<String, Comparable> m1 = _coinData[ascending ? s1 : s2],
        m2 = _coinData[ascending ? s2 : s1];
    dynamic v1 = m1[sortVal], v2 = m2[sortVal];
    if (sortVal == "name") {
      v1 = v1.toUpperCase();
      v2 = v2.toUpperCase();
    }
    int comp = v1.compareTo(v2);
    if (comp == 0) {
      return sortBy("nameA")(s1, s2) as int;
    }
    return comp;
  };
}

class _ListPageState extends State<ListPage> {
  bool searching = false;

  List<String> sortedKeys;
  String prevSearch = "";

  void reset() {
    if (widget.savedPage) {
      sortedKeys = List.from(_savedCoins)..sort(sortBy(sortingBy));
    } else {
      sortedKeys = List.from(_coinData.keys)..sort(sortBy(sortingBy));
    }
    setState(() {});
  }

  void search(String s) {
    scrollController.jumpTo(0.0);
    reset();
    moving = false;
    moveWith = null;
    for (int i = 0; i < sortedKeys.length; i++) {
      String key = sortedKeys[i];
      String name = _coinData[key]["name"];
      String ticker = _coinData[key]["symbol"];
      if (![name, ticker]
          .any((w) => w.toLowerCase().contains(s.toLowerCase()))) {
        sortedKeys.removeAt(i--);
      }
    }
    prevSearch = s;
    setState(() {});
  }

  void sort(String s) {
    scrollController.jumpTo(0.0);
    moving = false;
    moveWith = null;
    sortingBy = s;
    setState(() {
      sortedKeys.sort(sortBy(s));
    });
  }

  @override
  void initState() {
    super.initState();
    sortingBy = widget.savedPage ? "custom" : "marketCapUsdD";
    reset();
  }

  Timer searchTimer;
  ScrollController scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    List<PopupMenuItem> l = [
      PopupMenuItem<String>(
          child: const Text(
            "Name Ascending",
            style: TextStyle(fontSize: 14),
          ),
          value: "nameA"),
      PopupMenuItem<String>(
          child: const Text(
            "Name Descending",
            style: TextStyle(fontSize: 14),
          ),
          value: "nameD"),
      PopupMenuItem<String>(
          child: const Text(
            "Price Ascending",
            style: TextStyle(fontSize: 14),
          ),
          value: "priceUsdA"),
      PopupMenuItem<String>(
          child: const Text(
            "Price Descending",
            style: TextStyle(fontSize: 14),
          ),
          value: "priceUsdD"),
      PopupMenuItem<String>(
          child: const Text(
            "Market Cap Ascending",
            style: TextStyle(fontSize: 14),
          ),
          value: "marketCapUsdA"),
      PopupMenuItem<String>(
          child: const Text(
            "Market Cap Descending",
            style: TextStyle(fontSize: 14),
          ),
          value: "marketCapUsdD"),
      PopupMenuItem<String>(
          child: const Text(
            "24H Change Ascending",
            style: TextStyle(fontSize: 14),
          ),
          value: "changePercent24HrA"),
      PopupMenuItem<String>(
          child: const Text(
            "24H Change Descending",
            style: TextStyle(fontSize: 14),
          ),
          value: "changePercent24HrD")
    ];
    if (widget.savedPage) {
      l.insert(
          0,
          PopupMenuItem<String>(
              child: const Text(
                "Custom",
                style: TextStyle(fontSize: 14),
              ),
              value: "custom"));
    }
    Widget ret = Scaffold(
      backgroundColor: Color(0XFF101010),
      drawer: widget.savedPage
          ? Drawer(
              child: Container(
                color: Color(0XFF151515),
                child: ListView(children: [
                  SizedBox(
                    height: 24,
                  ),
                  GestureDetector(
                      child: Container(
                        color: Colors.black,
                        height: MediaQuery.of(context).size.height / 5,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.asset(
                              'assets/icon/icon_.png',
                              height: 45,
                            ),
                            SizedBox(
                              width: 0,
                            ),
                            Text(
                              'tracecoin',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 35,
                                  fontWeight: FontWeight.bold),
                            ),
                            SizedBox(
                              width: 8,
                            ),
                          ],
                        ),
                      ),
                      onTap: () async {
                        String url =
                            "https://www.linkedin.com/in/paul-kolawole/";
                        if (await canLaunch(url)) {
                          await launch(url);
                        }
                      }),
                  // ListTile(
                  //     leading: Icon(Icons.import_export),
                  //     title: Text("Import/Export Favorites",
                  //         style: TextStyle(fontSize: 16.0)),
                  //     onTap: () {
                  //       if (!_loading) {
                  //         _didImport = false;
                  //         Navigator.push(
                  //             context,
                  //             MaterialPageRoute(
                  //                 builder: (context) => ImpExpPage())).then((f) {
                  //           if (_didImport) {
                  //             _didImport = false;
                  //             searching = false;
                  //             reset();
                  //           }
                  //           setState(() {});
                  //         });
                  //       }
                  //     }),
                  // Padding(
                  //   padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  //   child: Divider(thickness: .2, color: Colors.white,),
                  // ),
                  SizedBox(
                    height: 4,
                  ),
                  ListTile(
                      leading: FaIcon(
                        FontAwesomeIcons.cog,
                        size: 20,
                      ),
                      title: Text("App Settings",
                          style: TextStyle(fontSize: 16.0)),
                      onTap: () {
                        if (!_loading) {
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => Settings()));
                        }
                      }),
                  SizedBox(
                    height: 4,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Divider(
                      height: .1,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(
                    height: 4,
                  ),
                  ListTile(
                      leading: FaIcon(
                        FontAwesomeIcons.solidEnvelope,
                        size: 20,
                      ),
                      title:
                          Text("Say Hi 👋", style: TextStyle(fontSize: 16.0)),
                      onTap: () async {
                        String url = Uri.encodeFull(
                            "mailto:kolawoleolufemi9@gmail.com?subject=GetPass&body=Contact Reason: ");
                        if (await canLaunch(url)) {
                          await launch(url);
                        }
                      }),
                  // ListTile(
                  //     leading: FaIcon(
                  //       FontAwesomeIcons.solidStar,
                  //       size: 20,
                  //     ),
                  //     title: Text("Rate Us", style: TextStyle(fontSize: 16.0)),
                  //     onTap: () async {
                  //       String url = Platform.isIOS
                  //           ? "https://itunes.apple.com/us/app/platypus-crypto/id1397122793"
                  //           : "https://play.google.com/store/apps/details?id=land.platypus.cryptotracker";
                  //       if (await canLaunch(url)) {
                  //         await launch(url);
                  //       }
                  //     }),
                  SizedBox(
                    height: 4,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Divider(
                      height: .1,
                      color: Colors.white,
                    ),
                  ),
                ]),
              ),
              key: ValueKey(widget.savedPage))
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      appBar: AppBar(
        backgroundColor: Color(0XFF101010),
        bottom: _loading
            ? PreferredSize(
                child: Container(
                  margin: EdgeInsets.symmetric(
                    horizontal: 16.0,
                  ),
                  color: Colors.white,
                  height: 1.5,
                  child: LinearProgressIndicator(),
                ),
                preferredSize: Size.fromHeight(0.0),
              )
            : PreferredSize(
                child: Container(
                  margin: EdgeInsets.symmetric(
                    horizontal: 16.0,
                  ),
                  color: Colors.white,
                  height: .1,
                  // child: LinearProgressIndicator(),
                ),
                preferredSize: Size.fromHeight(0.0),
              ),
        title: searching
            ? TextField(
                autocorrect: false,
                autofocus: true,
                decoration: InputDecoration(
                    hintText: "Search",
                    hintStyle: TextStyle(color: Colors.white),
                    border: InputBorder.none),
                style: TextStyle(color: Colors.white),
                onChanged: (s) {
                  searchTimer?.cancel();
                  searchTimer = Timer(Duration(milliseconds: 500), () {
                    search(s);
                  });
                },
                onSubmitted: (s) {
                  search(s);
                })
            : Text(
                widget.savedPage ? "Favourites" : " Top Markets",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
        actions: [
          IconButton(
              icon: Icon(searching ? Icons.close : Icons.search),
              onPressed: () {
                if (_loading) {
                  return;
                }
                setState(() {
                  if (searching) {
                    searching = false;
                    reset();
                  } else {
                    searching = true;
                  }
                });
              }),
          Container(
              width: 35.0,
              child: PopupMenuButton(
                  color: Color(0XFF252525),
                  enabled: true,
                  // elevation: 0,
                  itemBuilder: (BuildContext context) => l,
                  child: Icon(Icons.sort),
                  onSelected: (s) {
                    if (_loading) {
                      return;
                    }
                    sort(s);
                  })),
          IconButton(
              icon: Icon(Icons.refresh),
              onPressed: () async {
                if (_loading) {
                  return;
                }
                searching = false;
                sortingBy = widget.savedPage ? "custom" : "marketCapUsdD";
                await context.findAncestorStateOfType<_AppState>().setUpData();
                reset();
              })
        ],
      ),
      body: Column(
        children: [
          if (!_loading)
            Expanded(
              flex: 4,
              child: ListView.builder(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  scrollDirection: Axis.vertical,
                  shrinkWrap: true,
                  physics: ScrollPhysics(),
                  itemBuilder: (context, i) => Column(
                        children: [
                          SizedBox(height: 4),
                          Crypto(sortedKeys[i], widget.savedPage),
                          // SizedBox(height: 4),
                        ],
                      ),
                  itemCount: sortedKeys.length,
                  controller: scrollController),
            )
          else
            Container(),
          widget.savedPage
              ? !_loading
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 8.0,
                      ),
                      child: CustomButton(
                        buttonColor: Color(0XFF202020),
                        text: 'Add Favorite',
                        onTap: () {
                          moving = false;
                          moveWith = null;
                          Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) => ListPage(false)))
                              .then((d) {
                            sortingBy = "custom";
                            searching = false;
                            reset();
                            scrollController.jumpTo(0.0);
                          });
                        },
                        icon: Icon(
                          Icons.add,
                          size: 18,
                        ),
                        // heroTag: "newPage",
                      ),
                    )
                  : Container()
              : !_loading
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 8.0,
                      ),
                      child: CustomButton(
                        buttonColor: Color(0XFF202020),
                        text: 'Go to Top',
                        onTap: () {
                          scrollController.jumpTo(0.0);
                        },
                        icon: Icon(Icons.arrow_upward, size: 18),
                        // heroTag: "jump"
                      ),
                    )
                  : Container(),
        ],
      ),
    );
    if (!widget.savedPage) {
      ret = WillPopScope(
          child: ret, onWillPop: () => Future<bool>(() => !_loading));
    }
    return ret;
  }
}

bool _didImport = false;

class ImpExpPage extends StatefulWidget {
  @override
  ImpExpPageState createState() => ImpExpPageState();
}

class ImpExpPageState extends State<ImpExpPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text("Import/Export")),
        body: Builder(
            builder: (context) => Container(
                child: Padding(
                    padding: EdgeInsets.only(top: 20.0, right: 15, left: 15),
                    child:
                        ListView(physics: ClampingScrollPhysics(), children: [
                      Card(
                        color: Colors.black12,
                        child: ListTile(
                            title: Text("Export Favorites"),
                            subtitle: Text("To your clipboard"),
                            trailing: Icon(Icons.file_upload),
                            onTap: () async {
                              await Clipboard.setData(ClipboardData(
                                  text: json.encode(_savedCoins)));
                              Scaffold.of(context).removeCurrentSnackBar();
                              Scaffold.of(context).showSnackBar(SnackBar(
                                  duration: Duration(milliseconds: 1000),
                                  content: Text("Copied to clipboard",
                                      style: TextStyle(color: Colors.white)),
                                  backgroundColor: Colors.grey[800]));
                            }),
                        margin: EdgeInsets.zero,
                      ),
                      SizedBox(height: 20),
                      Card(
                        color: Colors.black12,
                        child: ListTile(
                            title: Text("Import Favorites"),
                            subtitle: Text("From your clipboard"),
                            trailing: Icon(Icons.file_download),
                            onTap: () async {
                              String str =
                                  (await Clipboard.getData("text/plain")).text;
                              try {
                                List<String> data =
                                    json.decode(str).cast<String>();
                                for (int i = 0; i < data.length; i++) {
                                  if (_coinData[data[i]] == null) {
                                    data.removeAt(i--);
                                  }
                                }
                                _savedCoins = data;
                                _userData["saved"] = data;
                                _didImport = true;
                                Scaffold.of(context).removeCurrentSnackBar();
                                Scaffold.of(context).showSnackBar(SnackBar(
                                    duration: Duration(milliseconds: 1000),
                                    content: Text("Imported",
                                        style: TextStyle(color: Colors.white)),
                                    backgroundColor: Colors.grey[800]));
                              } catch (e) {
                                Scaffold.of(context).removeCurrentSnackBar();
                                Scaffold.of(context).showSnackBar(SnackBar(
                                    duration: Duration(milliseconds: 1000),
                                    content: Text("Invalid data",
                                        style: TextStyle(color: Colors.white)),
                                    backgroundColor: Colors.grey[800]));
                              }
                            }),
                        margin: EdgeInsets.zero,
                      ),
                    ])))));
  }
}

class Settings extends StatefulWidget {
  @override
  SettingsState createState() => SettingsState();
}

class SettingsState extends State<Settings> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: Color(0XFF101010),
        appBar: AppBar(
          title: Text("Settings", style: TextStyle()),
          backgroundColor: Color(0XFF101010),
        ),
        body: Padding(
            padding: EdgeInsets.only(top: 20.0, right: 15, left: 15),
            child: ListView(physics: ClampingScrollPhysics(), children: [
              Card(
                color: Color(0XFF202020),
                child: ListTile(
                    title: Text("Disable 7 day graphs"),
                    subtitle: Text("More compact cards"),
                    trailing: Switch(
                        value: _settings["disableGraphs"],
                        onChanged: (disp) {
                          context
                              .findAncestorStateOfType<_AppState>()
                              .setState(() {
                            _settings["disableGraphs"] =
                                !_settings["disableGraphs"];
                          });
                          _userData["settings/disableGraphs"] =
                              _settings["disableGraphs"];
                        }),
                    onTap: () {
                      context.findAncestorStateOfType<_AppState>().setState(() {
                        _settings["disableGraphs"] =
                            !_settings["disableGraphs"];
                      });
                      _userData["settings/disableGraphs"] =
                          _settings["disableGraphs"];
                    }),
                margin: EdgeInsets.zero,
              ),
              Container(height: 16),
              Card(
                color: Color(0XFF202020),
                child: ListTile(
                    title: Text("Change Currency"),
                    subtitle: Text("33 fiat currency options"),
                    trailing: Padding(
                        child: Container(
                            color: Colors.white12,
                            padding: EdgeInsets.only(right: 12.0, left: 12.0),
                            child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                    value: _settings["currency"],
                                    onChanged: (s) {
                                      _settings["currency"] = s;
                                      _changeCurrency(s);
                                      _userData["settings/currency"] = s;
                                      context
                                          .findAncestorStateOfType<_AppState>()
                                          .setState(() {});
                                    },
                                    items: _supportedCurrencies
                                        .map((s) => DropdownMenuItem(
                                            value: s,
                                            child: Text(
                                              "$s ${_conversionMap[s]["symbol"]}",
                                              style: TextStyle(fontSize: 14),
                                            )))
                                        .toList()))),
                        padding: EdgeInsets.only(right: 10.0))),
                margin: EdgeInsets.zero,
              )
            ])));
  }
}

class PriceText extends StatefulWidget {
  final String id;

  PriceText(this.id);

  @override
  _PriceTextState createState() => _PriceTextState();
}

class _PriceTextState extends State<PriceText> {
  Color changeColor;
  Timer updateTimer;
  bool disp = false;
  ValueNotifier<num> coinNotif;
  Map<String, dynamic> data;

  void update() {
    if (data["priceUsd"].compareTo(coinNotif.value) > 0) {
      changeColor = Colors.green;
    } else {
      changeColor = Colors.red;
    }
    setState(() {});
    updateTimer?.cancel();
    updateTimer = Timer(Duration(milliseconds: 400), () {
      if (disp) {
        return;
      }
      setState(() {
        changeColor = null;
      });
    });
  }

  @override
  void initState() {
    super.initState();
    data = _coinData[widget.id];
    coinNotif = _valueNotifiers[widget.id];
    coinNotif.addListener(update);
  }

  @override
  void dispose() {
    super.dispose();
    disp = true;
    coinNotif.removeListener(update);
  }

  @override
  Widget build(BuildContext context) {
    num price = data["priceUsd"] * _exchangeRate;
    return Text(
        price >= 0
            ? NumberFormat.currency(
                    symbol: _symbol,
                    decimalDigits: price > 1
                        ? price < 100000
                            ? 2
                            : 0
                        : price > .000001
                            ? 6
                            : 7)
                .format(price)
            : "N/A",
        style: TextStyle(
            fontSize: 20.0, fontWeight: FontWeight.bold, color: changeColor));
  }
}

bool moving = false;
String moveWith;

class Crypto extends StatefulWidget {
  final String id;
  final bool savedPage;

  Crypto(this.id, this.savedPage)
      : super(key: ValueKey(id + savedPage.toString()));

  @override
  _CryptoState createState() => _CryptoState();
}

class _CryptoState extends State<Crypto> {
  bool saved;
  Map<String, dynamic> data;

  @override
  void initState() {
    super.initState();
    data = _coinData[widget.id];
    saved = _savedCoins.contains(widget.id);
  }

  void move(List<String> coins) {
    int moveTo = coins.indexOf(widget.id);
    int moveFrom = coins.indexOf(moveWith);
    coins.removeAt(moveFrom);
    coins.insert(moveTo, moveWith);
  }

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    num mCap = data["marketCapUsd"];
    mCap *= _exchangeRate;
    num change = data["changePercent24Hr"];
    String shortName = data["symbol"];
    return Container(
        decoration: BoxDecoration(
            color: !widget.savedPage
                ? saved
                    ? Color(0XFF181818)
                    : Color(0XFF181818)
                : Color(0XFF181818),
            borderRadius: BorderRadius.circular(4),
            border: !widget.savedPage
                ? saved
                    ? Border.all(color: Colors.white, width: .15)
                    : Border.all(color: Colors.white24, width: .15)
                : Border.all(color: Colors.white, width: .15)),
        child: GestureDetector(
            onLongPress: () {
              if (sortingBy == "custom") {
                context.findAncestorStateOfType<_ListPageState>().setState(() {
                  moving = true;
                  moveWith = widget.id;
                });
              } else if (!widget.savedPage) {
                Get.to(ItemInfo(widget.id), transition: Transition.rightToLeft);
              }
            },
            child: Dismissible(
                background: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: Colors.red[800],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SvgPicture.asset(
                          'assets/svgs/delete.svg',
                          width: 22,
                        ),
                      ],
                    ),
                  ),
                ),
                key: ValueKey(widget.id),
                direction: DismissDirection.endToStart,
                onDismissed: (d) {
                  _savedCoins.remove(widget.id);
                  _userData["saved"] = _savedCoins;
                  context
                      .findAncestorStateOfType<_ListPageState>()
                      .sortedKeys
                      .remove(widget.id);
                  context
                      .findAncestorStateOfType<_ListPageState>()
                      .setState(() {});
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 16.0,
                    horizontal: 16.0,
                  ),
                  child: InkWell(
                    onTap: () {
                      if (widget.savedPage) {
                        if (moving) {
                          move(_savedCoins);
                          move(context
                              .findAncestorStateOfType<_ListPageState>()
                              .sortedKeys);
                          setState(() {
                            moveWith = null;
                            moving = false;
                          });
                          context
                              .findAncestorStateOfType<_ListPageState>()
                              .setState(() {});
                          _userData["saved"] = _savedCoins;
                        } else {
                          Get.to(ItemInfo(widget.id),
                              transition: Transition.rightToLeft);
                        }
                      } else {
                        setState(() {
                          if (saved) {
                            saved = false;
                            _savedCoins.remove(widget.id);
                            _userData["saved"] = _savedCoins;
                          } else {
                            saved = true;
                            _savedCoins.add(widget.id);
                            _userData["saved"] = _savedCoins;
                          }
                        });
                      }
                    },
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(0.0),
                          child: Container(
                            height: 45,
                            width: 45,
                            decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: Colors.white.withOpacity(0.25)),
                            child: Center(
                              child: ClipRRect(
                                borderRadius:
                                    BorderRadius.all(Radius.circular(50)),
                                child: FadeInImage.assetNetwork(
                                    fit: BoxFit.cover,
                                    image: !blacklist.contains(widget.id)
                                        ? "https://static.coincap.io/assets/icons/${shortName.toLowerCase()}@2x.png"
                                        : "assets/images/b.png",
                                    placeholder: "assets/images/b.png",
                                    imageErrorBuilder:
                                        (context, obj, stackTrace) =>
                                            Image.asset(
                                              'assets/images/b.png',
                                              fit: BoxFit.cover,
                                            ),
                                    fadeInDuration:
                                        const Duration(milliseconds: 100),
                                    height: 32.0,
                                    width: 32.0),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ConstrainedBox(
                                    constraints:
                                        BoxConstraints(maxWidth: width / 3),
                                    child: AutoSizeText(
                                      data["name"],
                                      maxLines: 2,
                                      minFontSize: 0.0,
                                      maxFontSize: 17.0,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.normal,
                                        color: Colors.white,
                                      ),
                                    )),
                                SizedBox(height: 4),
                                Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      PriceText(widget.id),
                                    ]),
                                // SizedBox(height: 2),
                                change != -1000000.0
                                    ? Text(
                                        ((change >= 0) ? "+" : "") +
                                            change.toStringAsFixed(3) +
                                            "\%",
                                        style: TextStyle(
                                          color: ((change >= 0)
                                              ? Colors.green
                                              : Colors.red),
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : Text("N/A"),
                              ]),
                        ),
                        !_settings["disableGraphs"]
                            ? linkMap[shortName] != null &&
                                    !blacklist.contains(widget.id)
                                ? SvgPicture.network(
                                    "https://www.coingecko.com/coins/${linkMap[shortName] ?? linkMap[widget.id]}/sparkline",
                                    placeholderBuilder:
                                        (BuildContext context) => Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                      ),
                                      width: 0,
                                      height: 15.0,
                                    ),
                                    width: 15.0,
                                    height: 15.0,
                                  )
                                : Container(
                                    height: 15.0,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                    ),
                                  )
                            : Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                ),
                              ),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              !widget.savedPage
                                  ? saved
                                      ? Icon(
                                          Icons.circle,
                                          color: Colors.green,
                                          size: 15,
                                        )
                                      : Icon(
                                          Icons.circle,
                                          color: Colors.white30,
                                          size: 15,
                                        )
                                  : Container(),
                              SizedBox(height: 4),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  ConstrainedBox(
                                      constraints: BoxConstraints(
                                          maxWidth: width / 3 - 40),
                                      child: AutoSizeText(
                                        '$shortName',
                                        maxLines: 1,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.normal,
                                          color: Colors.white,
                                        ),
                                      )),
                                  SizedBox(height: 2),
                                  Text(
                                      (mCap >= 0
                                          ? mCap > 1
                                              ? _symbol +
                                                  NumberFormat.currency(
                                                          symbol: "",
                                                          decimalDigits: 0)
                                                      .format(mCap)
                                              : _symbol +
                                                  mCap.toStringAsFixed(2)
                                          : "N/A"),
                                      style: TextStyle(
                                          color: Colors.grey, fontSize: 12.0)),
                                ],
                              ),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                ))));
  }
}

class ItemInfo extends StatefulWidget {
  final String id;

  ItemInfo(this.id);

  @override
  _ItemInfoState createState() => _ItemInfoState();
}

class _ItemInfoState extends State<ItemInfo> {
  Map<String, dynamic> data;

  @override
  void initState() {
    super.initState();
    data = _coinData[widget.id];
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
        length: 5,
        child: Scaffold(
            backgroundColor: Color(0XFF101010),
            appBar: AppBar(
              elevation: 0,
              backgroundColor: Color(0XFF101010),
              title: Row(
                children: [
                  Container(
                    height: 38,
                    width: 38,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.white24,
                    ),
                    child: Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.all(Radius.circular(50)),
                        child: FadeInImage.assetNetwork(
                            fit: BoxFit.cover,
                            image: !blacklist.contains(widget.id)
                                ? "https://static.coincap.io/assets/icons/${data["symbol"].toLowerCase()}@2x.png"
                                : "assets/images/b.png",
                            placeholder: "assets/images/b.png",
                            imageErrorBuilder: (context, obj, stackTrace) =>
                                Image.asset(
                                  'assets/images/b.png',
                                  fit: BoxFit.cover,
                                ),
                            fadeInDuration: const Duration(milliseconds: 100),
                            height: 32.0,
                            width: 32.0),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 12,
                  ),
                  Text(
                    data["name"],
                    style: TextStyle(
                      fontSize: 18,
                      color: Color(0XFFF4F4F4),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              actions: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      data["symbol"],
                      style: TextStyle(
                        fontSize: 15,
                        color: Color(0XFFF4F4F4),
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ),
                )
              ],
            ),
            body: ListView(physics: ClampingScrollPhysics(), children: [
              SizedBox(
                height: 12,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Container(
                    color: Color(0XFF101010),
                    child: TabBar(tabs: [
                      Tab(
                          icon: AutoSizeText("1D",
                              maxFontSize: 15.0,
                              style: TextStyle(
                                  fontSize: 15.0, fontWeight: FontWeight.bold),
                              minFontSize: 0.0)),
                      Tab(
                          icon: AutoSizeText("7D",
                              maxFontSize: 15.0,
                              style: TextStyle(
                                  fontSize: 15.0, fontWeight: FontWeight.bold),
                              minFontSize: 0.0)),
                      Tab(
                          icon: AutoSizeText("1M",
                              maxFontSize: 15.0,
                              style: TextStyle(
                                  fontSize: 15.0, fontWeight: FontWeight.bold),
                              minFontSize: 0.0)),
                      Tab(
                          icon: AutoSizeText("6M",
                              maxFontSize: 15.0,
                              style: TextStyle(
                                  fontSize: 15.0, fontWeight: FontWeight.bold),
                              minFontSize: 0.0)),
                      Tab(
                          icon: AutoSizeText("1Y",
                              maxFontSize: 15.0,
                              style: TextStyle(
                                  fontSize: 15.0, fontWeight: FontWeight.bold),
                              minFontSize: 0.0)),
                    ])),
              ),
              SizedBox(
                height: 24,
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0, left: 8.0),
                child: Container(
                    height: 220.0,
                    padding: EdgeInsets.only(right: 10.0),
                    child: TabBarView(
                        physics: NeverScrollableScrollPhysics(),
                        children: [
                          SimpleTimeSeriesChart(widget.id, 1, "m5"),
                          SimpleTimeSeriesChart(widget.id, 7, "m30"),
                          SimpleTimeSeriesChart(widget.id, 30, "h2"),
                          SimpleTimeSeriesChart(widget.id, 182, "h12"),
                          SimpleTimeSeriesChart(widget.id, 364, "d1"),
                        ])),
              ),
              SizedBox(
                height: 24,
              ),
              Padding(
                padding: const EdgeInsets.only(left: 16.0),
                child: Text(
                  'Status',
                  style: TextStyle(
                    fontSize: 15,
                    color: Color(0XFFF4F4F4),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(
                height: 12,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Divider(
                  thickness: .1,
                  height: .5,
                  color: Colors.white,
                ),
              ),
              SizedBox(
                height: 12,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Column(
                  children: [
                    Row(children: [
                      Expanded(child: Info("Price", widget.id, "priceUsd")),
                      Expanded(
                          child: Info("Market Cap", widget.id, "marketCapUsd"))
                    ]),
                    Row(children: [
                      Expanded(child: Info("Supply", widget.id, "supply")),
                      Expanded(
                          child: Info("Max Supply", widget.id, "maxSupply")),
                    ]),
                    Row(children: [
                      Expanded(
                          child: Info(
                              "24h Change", widget.id, "changePercent24Hr")),
                      Expanded(
                          child: Info("24h Volume", widget.id, "volumeUsd24Hr"))
                    ]),
                  ],
                ),
              ),
            ])));
  }
}

class Info extends StatefulWidget {
  final String title, ticker, id;

  Info(this.title, this.ticker, this.id);

  @override
  _InfoState createState() => _InfoState();
}

class _InfoState extends State<Info> {
  dynamic value;

  ValueNotifier<num> coinNotif;

  Color textColor;

  Timer updateTimer;

  bool disp = false;

  Map<String, dynamic> data;

  void update() {
    if (data["priceUsd"].compareTo(coinNotif.value) > 0) {
      textColor = Colors.green;
    } else {
      textColor = Colors.red;
    }
    setState(() {});
    updateTimer?.cancel();
    updateTimer = Timer(Duration(milliseconds: 400), () {
      if (disp) {
        return;
      }
      setState(() {
        textColor = null;
      });
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.id == "priceUsd") {
      coinNotif = _valueNotifiers[widget.ticker];
      coinNotif.addListener(update);
    } else {
      textColor = Colors.white;
    }
    data = _coinData[widget.ticker];
  }

  @override
  void dispose() {
    super.dispose();
    if (widget.id == "priceUsd") {
      disp = true;
      coinNotif.removeListener(update);
    }
  }

  @override
  Widget build(BuildContext context) {
    dynamic value = data[widget.id];
    String text;
    if ((widget.id == "changePercent24Hr" && value == -1000000) ||
        value == null ||
        value == -1) {
      text = "N/A";
    } else {
      NumberFormat formatter;
      if (widget.id == "priceUsd") {
        formatter = NumberFormat.currency(
            symbol: _symbol,
            decimalDigits: value > 1
                ? value < 100000
                    ? 2
                    : 0
                : value > .000001
                    ? 6
                    : 7);
      } else if (widget.id == "marketCapUsd") {
        formatter = NumberFormat.currency(
            symbol: _symbol, decimalDigits: value > 1 ? 0 : 2);
      } else if (widget.id == "changePercent24Hr") {
        formatter = NumberFormat.currency(symbol: "", decimalDigits: 3);
      } else {
        formatter = NumberFormat.currency(symbol: "", decimalDigits: 0);
      }
      text = formatter.format(value);
    }
    if (widget.id == "changePercent24Hr" && value != -1000000) {
      text += "%";
      text = (value > 0 ? "+" : "") + text;
      textColor = value < 0
          ? Colors.red
          : value > 0
              ? Colors.green
              : Colors.white;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 0.0,
      ),
      child: Container(
        padding: EdgeInsets.only(top: 8.0, left: 4.0, right: 4.0),
        child: Container(
          height: 60.0,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: Colors.transparent,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title,
                  textAlign: TextAlign.left,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.normal)),
              SizedBox(height: 2),
              ConstrainedBox(
                child: AutoSizeText(text,
                    minFontSize: 0,
                    maxFontSize: 17,
                    style: TextStyle(
                        fontSize: 20,
                        color: textColor,
                        fontWeight: FontWeight.bold),
                    maxLines: 1),
                constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width / 2 - 8),
              )
            ],
          ),
        ),
      ),
    );
  }
}

class TimeSeriesPrice {
  DateTime time;
  double price;

  TimeSeriesPrice(this.time, this.price);
}

class SimpleTimeSeriesChart extends StatefulWidget {
  final String period, id;

  final int startTime;

  SimpleTimeSeriesChart(this.id, this.startTime, this.period);

  @override
  _SimpleTimeSeriesChartState createState() => _SimpleTimeSeriesChartState();
}

class _SimpleTimeSeriesChartState extends State<SimpleTimeSeriesChart> {
  List<TimeSeriesPrice> seriesList;
  double count = 0.0;
  double selectedPrice = -1.0;
  DateTime selectedTime;
  bool canLoad = true, loading = true;
  int base;
  num minVal, maxVal;

  @override
  void initState() {
    super.initState();
    DateTime now = DateTime.now();
    http
        .get(Uri.encodeFull(
            "https://api.coincap.io/v2/assets/${widget.id}/history?interval=" +
                widget.period +
                "&start=" +
                now
                    .subtract(Duration(days: widget.startTime))
                    .millisecondsSinceEpoch
                    .toString() +
                "&end=" +
                now.millisecondsSinceEpoch.toString()))
        .then((value) {
      seriesList = createChart(json.decode(value.body), widget.id);
      setState(() {
        loading = false;
      });
      base = minVal >= 0 ? max(0, (-log(minVal) / log(10)).ceil() + 2) : 0;
      if (minVal <= 1.1 && minVal > .9) {
        base++;
      }
    });
  }

  Map<String, int> dataPerDay = {
    "m5": 288,
    "m30": 48,
    "h2": 12,
    "h12": 2,
    "d1": 1
  };

  Map<String, DateFormat> formatMap = {
    "m5": DateFormat("h꞉mm a"),
    "m30": DateFormat.MMMd(),
    "h2": DateFormat.MMMd(),
    "h12": DateFormat.MMMd(),
    "d1": DateFormat.MMMd(),
  };

  @override
  Widget build(BuildContext context) {
    bool hasData = seriesList != null &&
        seriesList.length > (widget.startTime * dataPerDay[widget.period] / 10);
    double dif, factor, visMax, visMin;
    DateFormat xFormatter = formatMap[widget.period];
    NumberFormat yFormatter = NumberFormat.currency(
        symbol: _symbol.toString().replaceAll("\.", ""),
        locale: "en_US",
        decimalDigits: base);
    if (!loading && hasData) {
      dif = (maxVal - minVal);
      factor = min(1, max(.2, dif / maxVal));
      visMin = max(0, minVal - dif * factor);
      visMax = visMin != 0 ? maxVal + dif * factor : maxVal + minVal;
    }
    return !loading && canLoad && hasData
        ? Container(
            width: 350.0 * MediaQuery.of(context).size.width / 375.0,
            height: 220.0,
            child: SfCartesianChart(
              series: <ChartSeries>[
                AreaSeries<TimeSeriesPrice, DateTime>(
                  dataSource: seriesList,
                  xValueMapper: (TimeSeriesPrice s, _) => s.time,
                  yValueMapper: (TimeSeriesPrice s, _) => s.price,
                  animationDuration: 0,
                  gradient: LinearGradient(
                      colors: [
                        Color(0XFF222222),
                        Color(0XFF111111),
                      ],
                      stops: [
                        0.5,
                        1.0
                      ],
                      begin: FractionalOffset.topCenter,
                      end: FractionalOffset.bottomCenter,
                      tileMode: TileMode.repeated),
                  borderWidth: 1.5,
                  borderColor: Colors.white,
                  dataLabelSettings: DataLabelSettings(),
                  color: Colors.white,
                )
              ],
              borderWidth: 0,
              plotAreaBorderWidth: 0,
              plotAreaBackgroundColor: Colors.transparent,
              primaryXAxis: DateTimeAxis(
                labelIntersectAction: AxisLabelIntersectAction.rotate45,
                dateFormat: xFormatter,
                majorGridLines: MajorGridLines(width: 0),
              ),
              primaryYAxis: NumericAxis(
                  numberFormat: yFormatter,
                  decimalPlaces: base,
                  visibleMaximum: visMax,
                  visibleMinimum: visMin,
                  majorGridLines: MajorGridLines(width: 0),
                  interval: (visMax - visMin) / 4.001),
              selectionGesture: ActivationMode.singleTap,
              selectionType: SelectionType.point,
              onAxisLabelRender: (a) {
                if (a.orientation == AxisOrientation.vertical) {
                  a.text = yFormatter.format(a.value);
                } else {
                  a.text = xFormatter
                      .format(DateTime.fromMillisecondsSinceEpoch(a.value));
                }
              },
              trackballBehavior: TrackballBehavior(
                activationMode: ActivationMode.singleTap,
                enable: true,
                shouldAlwaysShow: false,
                // lineColor: Colors.lightBlue,
                hideDelay: 1,
                lineWidth: .3,
                lineType: TrackballLineType.vertical,
              ),
              onTrackballPositionChanging: (a) {
                var v = a.chartPointInfo.chartDataPoint;
                a.chartPointInfo.label =
                    "${xFormatter.format(v.x)} | ${yFormatter.format(v.y)}";
              },
            ))
        : canLoad && (hasData || loading)
            ? Container(
                height: 233.0,
                padding: EdgeInsets.only(left: 10.0, right: 10.0),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        strokeWidth: .8,
                      )
                    ]))
            : Container(
                height: 233.0,
                child: Center(
                    child: Text("Sorry, this coin graph is not supported",
                        style: TextStyle(fontSize: 17.0))));
  }

  List<TimeSeriesPrice> createChart(Map<String, dynamic> info, String s) {
    List<TimeSeriesPrice> data = [];

    if (info != null && info.length > 1) {
      for (int i = 0; i < info["data"].length; i++) {
        num val = num.parse(info["data"][i]["priceUsd"]) * _exchangeRate;
        minVal = min(minVal ?? val, val);
        maxVal = max(maxVal ?? val, val);
        data.add(TimeSeriesPrice(
            DateTime.fromMillisecondsSinceEpoch(info["data"][i]["time"]), val));
      }
    } else {
      canLoad = false;
    }
    return data;
  }
}
