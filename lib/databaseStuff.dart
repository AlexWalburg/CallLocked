import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:CallLock/constants.dart' as constants;

import 'package:image_picker/image_picker.dart';
import 'package:qrscan/qrscan.dart' as scanner;

void addNumberViaText(BuildContext context) async{
  String numToEncrypt = "";
  String code = "";
  void addImageForReal() async{
    String pem = code.substring(code.indexOf("\n")+1);
    int listingNum = int.parse(code.substring(0,code.indexOf("\n")));
    var encoder = constants.RsaKeyHelper();
    var pubKey = encoder.parsePublicKeyFromPem(pem);
    var encodedNum = encoder.encrypt(numToEncrypt, pubKey);
    var listingMaker = ListingMaker();
    var listing = Listing.fromMap({"id": listingNum,"phoneNum" : numToEncrypt});
    await listingMaker.open();
    listingMaker.insert(listing);
    constants.Constants.registerListing(listingNum, encodedNum);
  }
  showDialog(
      context: context,
      child: SimpleDialog(
        title: Text("Add A Number From Text"),
        contentPadding: EdgeInsets.all(15),
        children: [
          TextField(
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(hintText: "Phone Number"),
            onChanged: (String input){numToEncrypt=input;},
          ),
          TextField(
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(hintText: "Key"),
            maxLines: null,
            onChanged: (String input){code=input;},
          ),
          RaisedButton(
            child: Text("Choose Image And Add File"),
            onPressed: addImageForReal,
          ),
        ],
      )
  );
}

void addNumberViaCamera(BuildContext context) async{
  String numToEncrypt = "";
  void addImageForReal() async{
    String code = await scanner.scan();

    String pem = code.substring(code.indexOf("\n")+1);
    int listingNum = int.parse(code.substring(0,code.indexOf("\n")));
    var encoder = constants.RsaKeyHelper();
    var pubKey = encoder.parsePublicKeyFromPem(pem);
    var encodedNum = encoder.encrypt(numToEncrypt, pubKey);
    var listingMaker = ListingMaker();
    var listing = Listing.fromMap({"id": listingNum,"phoneNum" : numToEncrypt});
    await listingMaker.open();
    listingMaker.insert(listing);
    constants.Constants.registerListing(listingNum, encodedNum);
  }
  showDialog(
      context: context,
      child: SimpleDialog(
        title: Text("Add A Number From Camera"),
        contentPadding: EdgeInsets.all(15),
        children: [
          TextField(
            keyboardType: TextInputType.phone,
            onChanged: (String input){numToEncrypt=input;},
            decoration: InputDecoration(hintText: "Phone Number"),
          ),
          RaisedButton(
            child: Text("Scan code and register number"),
            onPressed: addImageForReal,
          ),
        ],
      )
  );
}
void addNumberViaImage(BuildContext context) async{
  String numToEncrypt = "";
  void addImageForReal() async{
    PickedFile image = await ImagePicker().getImage(source: ImageSource.gallery);
    if(image==null){
      return;
    }
    String code = await scanner.scanPath(image.path);
    String pem = code.substring(code.indexOf("\n")+1);
    int listingNum = int.parse(code.substring(0,code.indexOf("\n")));
    var encoder = constants.RsaKeyHelper();
    var pubKey = encoder.parsePublicKeyFromPem(pem);
    var encodedNum = encoder.encrypt(numToEncrypt, pubKey);
    var listingMaker = ListingMaker();
    var listing = Listing.fromMap({"id": listingNum,"phoneNum" : numToEncrypt});
    await listingMaker.open();
    listingMaker.insert(listing);
    constants.Constants.registerListing(listingNum, encodedNum);
  }
  showDialog(
      context: context,
      child: SimpleDialog(
        title: Text("Add A Number From A File"),
        contentPadding: EdgeInsets.all(15),
        children: [
          TextField(
            keyboardType: TextInputType.phone,
            onChanged: (String input){numToEncrypt=input;},
            decoration: InputDecoration(hintText: "Phone Number"),
            style: TextStyle(),
          ),
          RaisedButton(
            child: Text("Choose Image And Add File"),
            onPressed: addImageForReal,
          ),
        ],
      )
  );
}
void clearDB() async{
  Database db = await openDatabase(join(await getDatabasesPath(),"dataBase.db"));
  await db.transaction((txn) async {
    await txn.delete("listings");
    await txn.delete("groups");
  });
}
void createDB() async{
  String path = join(await getDatabasesPath(),"dataBase.db");
  Database db = await openDatabase(path, version: 1,
  onCreate: (Database db, int version) async{
    await db.execute('Create table listings (id integer, phoneNum text)');
    await db.execute('Create table groups (id integer, deleteKey text, name text, privkey text, pubkey text, timestamp integer)');
  });
}
Future<List<Map<String,dynamic>>> getGroups() async{
  Database db = await openDatabase(join(await getDatabasesPath(),"dataBase.db"));
  return await db.query('groups');
}
class Listing{
  int id;
  String phoneNum;
  Map<String, dynamic> toMap(){
    return <String,dynamic>{
      "id": id,
      "phoneNum": phoneNum
    };
  }
  Listing.fromMap(Map<String,dynamic> map){
    id = map["id"];
    phoneNum = map["phoneNum"];
  }

}

class ListingMaker{
  Database db;
  Future open() async {
    db = await openDatabase(join(await getDatabasesPath(), "dataBase.db"));
  }
  Future close() async => db.close();
  Future<int> delete(String phoneNum) async {
    return await db.delete('listings', where: 'phoneNum like ?',whereArgs: [phoneNum]);
  }
  Future<int> update(Listing entry) async {
    return await db.update('listings', entry.toMap(), where: 'phoneNum like ? and id=?', whereArgs: [entry.phoneNum,entry.id]);
  }
  Future<int> insert(Listing entry) async{
    return await db.insert('listings', entry.toMap());
  }
  Future<List<Listing>> getListings(int id) async {
    List<Map> maps = await db.query('listings', columns: ['id', 'phoneNum'], where: 'id=?', whereArgs: [id]);
    List<Listing> toReturn = new List();
    for(Map m in maps){
      toReturn.add(Listing.fromMap(m));
    }
    return toReturn;
  }
}

class Group{
  int id, timestamp;
  String deleteKey, name, privkey, pubkey;
  Map<String, dynamic> toMap(){
    return <String,dynamic>{
      "id": id,
      "deleteKey": deleteKey,
      "name": name,
      "privkey": privkey,
      "pubkey" : pubkey,
      "timestamp" : timestamp,
    };
  }
  Group.fromMap(Map<String,dynamic> map){
    id = map["id"];
    deleteKey = map["deleteKey"];
    name = map["name"];
    privkey = map["privkey"];
    pubkey = map["pubkey"];
    timestamp = map["timestamp"];
  }
  Group(int id, String deleteKey, String name, String privkey, String pubkey){
    this.id = id;
    this.deleteKey = deleteKey;
    this.name = name;
    this.privkey = privkey;
    this.pubkey = pubkey;
    this.timestamp = 0;
  }
}

class GroupMaker{
  Database db;
  Future open() async {
    db = await openDatabase(join(await getDatabasesPath(),"dataBase.db"));
  }
  Future close() async => db.close();
  Future<int> delete(int id) async {
    print(db.isOpen);
    return await db.delete('groups', where: 'id=?', whereArgs: [id]);
  }
  Future<int> update(Group entry) async{
    return await db.update("groups", entry.toMap(),where: 'id=?', whereArgs: [entry.id]);
  }
  Future<int> insert(Group entry) async{
    return await db.insert("groups", entry.toMap());
  }
  Future<Group> getGroup(int id) async {
    List<Map> maps = await db.query('groups', where: 'id=?', whereArgs: [id]);
    if(maps.length > 0){
      return Group.fromMap(maps.first);
    } else {
      return null;
    }
  }
}