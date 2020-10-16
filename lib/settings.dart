import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'databaseStuff.dart' as databaseStuff;

import 'navigator.dart';

class SettingsPage extends StatefulWidget{
  @override
  SettingsPageState createState() => SettingsPageState();
}
class SettingsPageState extends State<SettingsPage>{
  void changeServerIP(String ip){

  }
  void changeResetTime(String min){

  }
  void reset(){
    databaseStuff.clearDB();
  }
  @override
  Widget build(BuildContext context) {
    // TODO: implement build
    return Scaffold(
      appBar: AppBar(title: Text("Settings")),
      body: Container(
        margin: EdgeInsets.symmetric(horizontal: 25.0),
        child: Center(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              TextField(
                decoration: InputDecoration(hintText: "Server IP"),
                onSubmitted: changeServerIP,
              ),
              TextField(
                decoration: InputDecoration(hintText: "Reset every Blank minutes",),
                keyboardType: TextInputType.number,
                onSubmitted: changeResetTime,
              ),
              RaisedButton(
                  child: Text("Reset"),
                  onPressed: reset),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
          currentIndex:3, //changes for each page, i hate the code reuse too
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
}