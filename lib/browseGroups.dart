import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'constants.dart';
import 'navigator.dart';

class BrowseGroupsPage extends StatefulWidget{
  @override
  BrowseGroupsPageState createState() => BrowseGroupsPageState();
}
class BrowseGroupsPageState extends State<BrowseGroupsPage>{
  final TextEditingController filter = new TextEditingController();
  String searchText = "";
  List<dynamic> groups;
  BrowseGroupsPageState(){
    filter.addListener(() {
      if (filter.text.isEmpty) {
        setState(() {
          searchText = "";
        });
      } else {
        setState(() {
          searchText = filter.text;
        });
      }
    });
  }
  void search() async{
     Constants.searchPublicGroups(searchText).then(
             (value){
               setState(() {
                groups = value;
               });
             });
  }
  Widget listBuilder(){
    return groups != null ?
      ListView.builder(
          itemCount: groups.length,
          itemBuilder: (BuildContext context, int i){
            return GroupPanel(group: groups[i]);
          })
        : Center(child: CircularProgressIndicator());
  }
  @override
  Widget build(BuildContext context) {
    // TODO: implement build
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: filter,
          onSubmitted: (value){search();},
          autofocus: true,
          decoration: new InputDecoration(
            prefixIcon: new Icon(Icons.search),
            hintText: 'Search...',
          )
        ),
        actions: [ElevatedButton(onPressed: search, child: Icon(Icons.search))
        ],
      ),
      body: Container(
          margin: EdgeInsets.symmetric(horizontal: 25.0),
          child: listBuilder()
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
class GroupPanel extends StatelessWidget{
  final List<dynamic> group;
  GlobalKey globalKey = new GlobalKey();


  GroupPanel({this.group});
  @override
  Widget build(BuildContext context) {
    return Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.all(Radius.circular(8.0))),
        child:Row(
            mainAxisAlignment: MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.center,
            children:[
              Container(
                  padding: EdgeInsets.symmetric(horizontal: 5.0),
                  color: Colors.green,
                  child:IconButton(
                    icon: Icon(Icons.add_circle_outline_rounded),
                    onPressed: (){
                      Constants.pullGroup(group[0].toString() + "\n" + group[2]);
                    },
                    splashColor: Colors.lightGreenAccent,)
              ),
              Expanded(child:Text(group[0].toString() + ": " + group[1], style: TextStyle(fontSize: 20.0,),textAlign: TextAlign.right,)),
            ]
        )
    );
  }
}
