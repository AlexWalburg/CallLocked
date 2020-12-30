import 'package:CallLock/browseGroups.dart';
import 'package:CallLock/manageGroups.dart';
import 'package:CallLock/navigator.dart';
import 'package:CallLock/settings.dart';
import 'package:flutter/material.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:CallLock/databaseStuff.dart';
const buttonStyle = TextStyle(fontSize: 26);
void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CallLock',
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
        primarySwatch: Colors.orange,
        // This makes the visual density adapt to the platform that you run
        // the app on. For desktop platforms, the controls will be smaller and
        // closer together (more dense) than on mobile platforms.
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: MyHomePage(title: 'CallLock'),
      routes: <String,WidgetBuilder>{
        "/settings": (BuildContext context) => SettingsPage(),
        "/manageGroups": (BuildContext context) => ManageGroupsPage(),
        "/browseGroups": (BuildContext context) => BrowseGroupsPage(),
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<String> contacts;

  Future<void> loadData() async {
    List<String> _contacts = [];
    if (await Permission.contacts.isGranted || await Permission.contacts
        .request()
        .isGranted) { //we use the ||'s feature to automatically skip if the first one returns true to branch automatically
      Iterable<Contact> cs = await ContactsService.getContacts(
          withThumbnails: false);
      for (Contact c in cs) {
        if (c.displayName != null)
          _contacts.add(c.displayName);
      }
      setState(() {
        contacts = _contacts;
      });
    }
  }



  @override
  void initState(){
    super.initState();
    createDB();
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
          child: Container(
              margin: EdgeInsets.symmetric(horizontal: 25.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  RaisedButton(child: Text("Sync Groups", style : buttonStyle),
                      onPressed: syncGroups,
                      shape: BeveledRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10.0))),
                      padding: EdgeInsets.symmetric(vertical: 25.0, horizontal: 4.0),
                  ),
                  RaisedButton(child: Text("Add Number To Group", style: buttonStyle),
                      shape: BeveledRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                      onPressed: (){
                          showDialog(
                            context: context,
                            child: SimpleDialog(
                              title: Text("Add Number To A Group"),

                              children: [
                                  Row(
                                    children: [
                                      Container(
                                          decoration: BoxDecoration(
                                            color: Colors.orange,
                                            borderRadius: BorderRadius.all(Radius.circular(8.0))
                                          ),
                                          child:IconButton(
                                              icon: Icon(Icons.article_outlined),
                                              onPressed: (){addNumberViaText(context);},
                                              iconSize: 50.0,
                                        )
                                      ),
                                      Container(
                                          decoration: BoxDecoration(
                                              color: Colors.blueAccent,
                                              borderRadius: BorderRadius.all(Radius.circular(8.0))
                                          ),
                                          child:IconButton(
                                            icon: Icon(Icons.camera_alt_outlined),
                                            onPressed: (){addNumberViaCamera(context);},
                                            iconSize: 50.0,
                                          )
                                      ),
                                      Container(
                                          decoration: BoxDecoration(
                                              color: Colors.green,
                                              borderRadius: BorderRadius.all(Radius.circular(8.0))
                                          ),
                                          child:IconButton(
                                            icon: Icon(Icons.upload_file),
                                            onPressed: (){addNumberViaImage(context);},
                                            iconSize: 50.0,
                                          )
                                      ),
                                    ],
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  )
                              ],
                            )
                          );
                      },
                      padding:EdgeInsets.symmetric(vertical:25.0,horizontal: 4.0)
                  ),
                  RaisedButton(child: Text("Add Group", style: buttonStyle),
                      shape: BeveledRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                      onPressed: (){
                        showDialog(
                            context: context,
                            child: SimpleDialog(
                              title: Text("Add A Group"),

                              children: [
                                Row(
                                  children: [
                                    Container(
                                        decoration: BoxDecoration(
                                            color: Colors.orange,
                                            borderRadius: BorderRadius.all(Radius.circular(8.0))
                                        ),
                                        child:IconButton(
                                          icon: Icon(Icons.article_outlined),
                                          onPressed: (){addGroupViaText(context);},
                                          iconSize: 50.0,
                                        )
                                    ),
                                    Container(
                                        decoration: BoxDecoration(
                                            color: Colors.blueAccent,
                                            borderRadius: BorderRadius.all(Radius.circular(8.0))
                                        ),
                                        child:IconButton(
                                          icon: Icon(Icons.camera_alt_outlined),
                                          onPressed: (){addGroupViaCamera(context);},
                                          iconSize: 50.0,
                                        )
                                    ),
                                    Container(
                                        decoration: BoxDecoration(
                                            color: Colors.green,
                                            borderRadius: BorderRadius.all(Radius.circular(8.0))
                                        ),
                                        child:IconButton(
                                          icon: Icon(Icons.upload_file),
                                          onPressed: (){addGroupViaImage(context);},
                                          iconSize: 50.0,
                                        )
                                    ),
                                  ],
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                )
                              ],
                            )
                        );
                      },
                      padding:EdgeInsets.symmetric(vertical:25.0,horizontal: 4.0)
                  ),
                ]
            )
        )
      ),
      bottomNavigationBar: BottomNavigationBar(
          currentIndex:0, //changes for each page, i hate the code reuse too
          selectedItemColor:Colors.amber,
          onTap: changePanel,
          backgroundColor: Colors.orange,
          unselectedItemColor: Colors.black54,
          items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
              icon: Icon(Icons.water_damage),
              label: "Home",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.all_inbox),
            label: "Manage Groups",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: "Browse Groups",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: "Settings",
          ),
        ]
      ),
    );
  }
  void changePanel(int index){
    Navigator.pushReplacement(context,navigate(index));
  }
  void syncGroups() async{

  }
  void addGroupPopUpCreator() async{

  }
}
