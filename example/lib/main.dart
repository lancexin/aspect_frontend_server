import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

//必须有,不然不起作用
import 'inject.dart';

void main() {
  runApp(const MyApp());
}

int total = 0;

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

Future<bool> _test4(int key1, String key2, {String key3 = 'namedkey4'}) async {
  total++;
  debugPrint("$total _test4 $key1 $key2 $key3");
  return true;
}

Future<bool> _testtry(int key1, String key2,
    {String key3 = 'namedkey4'}) async {
  try {
    total++;
    debugPrint("$total testtry $key1 $key2 $key3");
    var arr = [];
    print(arr[10]);
  } catch (error) {}
  return true;
}

extension ExtensionHomePageState on _MyHomePageState {
  Future<bool> _test5(int key1, String key2,
      {String key3 = 'namedkey5'}) async {
    total++;
    debugPrint("$total _test5 $key1 $key2 $key3");
    return false;
  }
}

mixin MixinHomePageState {
  void _test6(int key1, String key2, {String key3 = 'namedkey6'}) {
    total++;
    debugPrint("$total _test6 $key1 $key2 $key3");
  }
}

class _MyHomePageState extends State<MyHomePage> with MixinHomePageState {
  int _counter = 0;

  void _test1(int key1, String key2, {String key3 = 'namedkey1'}) {
    total++;
    debugPrint("$total _test1 $key1 $key2 $key3");
  }

  Future<bool> _test2(int key1, String key2,
      {String key3 = 'namedkey2'}) async {
    total++;
    debugPrint("$total _test2 $key1 $key2 $key3");
    return true;
  }

  static Future<bool> _test3(int key1, String key2,
      {String key3 = 'namedkey3'}) async {
    total++;
    debugPrint("$total _test3 $key1 $key2 $key3");
    return true;
  }

  void _incrementCounter() {
    total = 0;
    _test1(_counter, "positional1");
    _test2(_counter, "positional2");
    _test3(_counter, "positional3");
    _test4(_counter, "positional4");
    _test5(_counter, "positional5");
    _test6(_counter, "positional6");
    _testtry(_counter, "positional7");
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Invoke "debug painting" (press "p" in the console, choose the
          // "Toggle Debug Paint" action from the Flutter Inspector in Android
          // Studio, or the "Toggle Debug Paint" command in Visual Studio Code)
          // to see the wireframe for each widget.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              'You have pushed the button this many times:',
            ),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headline4,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
