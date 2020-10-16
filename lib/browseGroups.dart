import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'navigator.dart';

class BrowseGroupsPage extends StatefulWidget{
  @override
  BrowseGroupsPageState createState() => BrowseGroupsPageState();
}
class BrowseGroupsPageState extends State<BrowseGroupsPage>{
  void search(){

  }
  @override
  Widget build(BuildContext context) {
    // TODO: implement build
    return Scaffold(
      appBar: AppBar(title: Text("Browse Groups"),actions: [ElevatedButton(onPressed: search, child: Icon(Icons.search))],),
      body: Container(
          margin: EdgeInsets.symmetric(horizontal: 25.0),
          child: ListView()
      ),
      bottomNavigationBar: BottomNavigationBar(
          currentIndex:2, //changes for each page, i hate the code reuse too
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