import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:CallLock/constants.dart';
import 'package:flutter/rendering.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share/share.dart';
import 'databaseStuff.dart' as databaseStuff;
import 'navigator.dart';

class ManageGroupsPage extends StatefulWidget{
  @override
  ManageGroupsPageState createState() => ManageGroupsPageState();
}
class ManageGroupsPageState extends State<ManageGroupsPage>{
  final TextEditingController filter = new TextEditingController();
  String groupName;
  String searchText = "";
  bool isPublic = false;
  Widget appBarTitle = Text("Manage Groups");
  Icon searchIcon = new Icon(Icons.search);
  List<String> contacts;
  List<Map<String,dynamic>> groups, filteredGroups;

  @override
  void initState(){
    super.initState();
    loadGroups();
  }
  Future<void> loadGroups() async{
    var _groups = await databaseStuff.getGroups();
    setState(() {
      groups = _groups;
      filteredGroups = _groups;
    });
  }
  ManageGroupsPageState(){
    filter.addListener(() {
      if (filter.text.isEmpty) {
        setState(() {
          searchText = "";
          filteredGroups = groups;
        });
      } else {
        setState(() {
          searchText = filter.text;
        });
      }
    });
  }
  Widget listBuilder(){
    if(searchText!=""){
      filteredGroups = new List();
      for(var group in groups){
        if(group["name"].toLowerCase().contains(searchText)){
          filteredGroups.add(group);
        }
      }
    } else {
      filteredGroups = groups;
    }
    return filteredGroups != null ? ListView.builder(itemCount: filteredGroups.length, itemBuilder: (BuildContext context, int i){return GroupPanel(group: databaseStuff.Group.fromMap(filteredGroups[i]));}) : Center(child: CircularProgressIndicator());
  }
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
  //TODO add in a search functionality
  void search() {
    setState(() {
      if (this.searchIcon.icon == Icons.search) {
        this.searchIcon = new Icon(Icons.close);
        this.appBarTitle = new TextField(
          controller: filter,
          autofocus: true,
          decoration: new InputDecoration(
              prefixIcon: new Icon(Icons.search),
              hintText: 'Search...',
          ),
        );
      } else {
        this.searchIcon = new Icon(Icons.search);
        this.appBarTitle = new Text('Search Example');
        filteredGroups = groups;
        filter.clear();
      }
    });
  }
  Widget addGroupDialogMaker(){
    return Container(
        margin: EdgeInsets.symmetric(horizontal: 10.0),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: InputDecoration(hintText: "Group name"),
                onChanged: _onChange,
              ),
              Row(
                  children: [
                    Checkbox(value: isPublic, onChanged: checkbox_onChange),
                    Text("Make group public?")
                  ]),
            ]
        )
    );
  }
  void _onChange(String input){
    setState(() {
      groupName=input;
    });
  }
  void checkbox_onChange(bool value) {
    setState(() {
      isPublic=value;
    });
  }
  @override
  Widget build(BuildContext context) {
    // TODO: implement build
    return Scaffold(
      appBar: AppBar(
        title: appBarTitle,
        actions: [
          ElevatedButton(
              onPressed: search,
              child: searchIcon
          ),
          ElevatedButton(
              onPressed: () {
                showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                        title: Text("Add a group"),
                        content: StatefulBuilder(builder: (context, setState) => Container(
                            margin: EdgeInsets.symmetric(horizontal: 10.0),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextField(
                                    decoration: InputDecoration(hintText: "Group name"),
                                    onChanged: _onChange,
                                  ),
                                  Row(
                                      children: [
                                        Checkbox(value: isPublic, onChanged: (bool value) {setState(() => isPublic = value);}),
                                        Text("Make group public?")
                                      ]),
                                ]
                            )
                        )),
                        actions: [
                          FlatButton(onPressed: (){Navigator.of(context).pop();}, child: Text("Cancel")),
                          RaisedButton(onPressed: (){Navigator.of(context).pop(); Constants.registerGroup(groupName, isPublic); }, child: Text("Confirm"))
                        ]
                    )
                );
              },
              child: Icon(Icons.add)
          )
        ],
      ),
      body:  listBuilder(),
      bottomNavigationBar: BottomNavigationBar(
          currentIndex:1, //changes for each page, i hate the code reuse too
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
  final databaseStuff.Group group;
  GlobalKey globalKey = new GlobalKey();


  GroupPanel({Key key, this.group}) : super(key: key);
  void sharePng() async {

    RenderRepaintBoundary boundary = globalKey.currentContext.findRenderObject();
    var image = await boundary.toImage();
    ByteData byteData = await image.toByteData(format: ImageByteFormat.png);
    Uint8List pngBytes = byteData.buffer.asUint8List();
    Constants.sharePng(pngBytes);
  }
  @override
  Widget build(BuildContext context) {
    return Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.all(Radius.circular(8.0))),
        child:Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.center,
          children:[
            Container(
                padding: EdgeInsets.symmetric(horizontal: 5.0),
                color: Colors.amber,
                child:IconButton(
                  icon: Icon(Icons.add_circle_outline_rounded),
                  onPressed: (){showDialog(
                    context: context,
                    child: SimpleDialog(
                      contentPadding: EdgeInsets.all(8.0),
                      children: [
                        Text("Warning: This is the ADD CONTACT dialog. If you share this with someone, they can add any number they want to your group."),
                        RaisedButton(
                            onPressed: (){Share.share("Hello! The person sending this wants you to register your number with them on CallLock. Just head over to calllock.github.io and use everything below the dashed line!\n-----\n" + group.id.toString() + "\n" + group.pubkey);},
                            child: Text("Share Text")
                        ),
                        RaisedButton(
                          onPressed: (){
                            sharePng();
                          },
                          child: Text("Share QR Code")
                        ),
                        RepaintBoundary(
                            key: globalKey,
                            child: QrImage(data: group.id.toString() + "\n" + group.pubkey,
                              errorCorrectionLevel: QrErrorCorrectLevel.L,
                              backgroundColor: Colors.white,
                              embeddedImage: AssetImage('graphics/CallLockLogoQRCode.png'),
                            )
                        )
                      ],
                    ),

                  );},
                  splashColor: Colors.orangeAccent,)
            ),
            Container(
                padding: EdgeInsets.symmetric(horizontal: 5.0),
                color: Colors.green,
                child:IconButton(
                  icon: Icon(Icons.share),
                  onPressed: (){showDialog(
                    context: context,
                    child: SimpleDialog(
                      contentPadding: EdgeInsets.all(8.0),
                      children: [
                        Text("Warning: This is the SHARE GROUP dialog. If you send this to someone, they can see every single number in the group!"),
                        RaisedButton(
                            onPressed: (){Share.share("The person sharing this just sent you a CallLock Group! Head over to the app to add it to your phone.\n-----\n" + group.id.toString() + "\n" + group.privkey);},
                            child: Text("Share Text")
                        ),
                        RaisedButton(
                            onPressed: (){
                              sharePng();
                            },
                            child: Text("Share QR Code")
                        ),
                        RepaintBoundary(
                            key: globalKey,
                            child: QrImage(data: group.id.toString() + "\n" + group.privkey,
                              errorCorrectionLevel: QrErrorCorrectLevel.L,
                              backgroundColor: Colors.white,
                              embeddedImage: AssetImage('graphics/CallLockLogoQRCode.png'),
                            )
                        )
                      ],
                    ),

                  );},
                  splashColor: Colors.orangeAccent,)
            ),
            Expanded(child:Text(group.id.toString() + ": " + group.name, style: TextStyle(fontSize: 20.0,),textAlign: TextAlign.center,)),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 5.0),
              color: Colors.orange,
              child: GestureDetector(
                onLongPress: (){
                  showDialog(
                    context: context,
                    child: AlertDialog(
                      content: Text("Are you sure you want to hard resync? This may take a while"),
                      actions: [
                        TextButton(
                            onPressed: (){Navigator.pop(context);}, child: Text("Cancel")),
                        RaisedButton(onPressed: (){Constants.hardSyncNums(group.id); Navigator.pop(context);}, child: Text("Resync")),
                      ],
                    )
                  );
                },
                child: IconButton(icon: Icon(Icons.autorenew), onPressed: (){
                  Constants.syncNums(group.id);
                },
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 5.0),
              color: Colors.red,
              child: IconButton(icon: Icon(Icons.delete_forever), onPressed: (){showDialog(
                child: AlertDialog(content: Text(
                    "Are you sure you want to delete this group? This is a permanent action which cannot be undone.\n (Warning: it takes some time to update that an entry is gone, try going to the home tab and back)"),
                  actions: [
                    TextButton(
                        onPressed: (){Navigator.pop(context);}, child: Text("Cancel")),
                    RaisedButton(onPressed: (){removeGroup(); Navigator.pop(context);}, child: Text("Delete")),
                  ],
                ),
                context: context,
              );}
              ),
            ),
          ]
      )
    );
  }

  void removeGroup() async{
    var manager = databaseStuff.GroupMaker();
    await manager.open();
    print(group.id);
    manager.delete(group.id);
  }


}

