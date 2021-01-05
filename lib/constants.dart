import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:pointycastle/export.dart';
import 'package:pointycastle/random/fortuna_random.dart';
import 'package:http/http.dart' as http;
import 'package:asn1lib/asn1lib.dart';
import 'package:CallLock/databaseStuff.dart';
import 'dart:math';
import 'dart:typed_data';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:share/share.dart';

class Constants {
  static String address = "http://192.168.4.54:5000";
  static void sharePng(Uint8List pngBytes) async {
    var file = new File(await getDatabasesPath() + "/CallLockTemp.png");
    await file.writeAsBytes(pngBytes);
    Share.shareFiles([file.path], mimeTypes: ['image/png']);
  }

  static void registerListing(int listingNum, String encryptedNumber, String encryptedName) async {
    await http.post(address + "/addNumber", body: {
      "listingId": listingNum.toString(),
      "encryptedPhoneNumber": encryptedNumber,
      "encryptedName" : encryptedName
    });
  }
  static Future<List<dynamic>> searchPublicGroups(String searchText) async{
    var response = jsonDecode(
        (await http.post(
            address + "/searchPublicListings",
          body: {
              "searchText": searchText
          }
        )
    ).body);
    print(response);
    return response;
  }
  static Future<Group> pullGroup(String idString) async {
    GroupMaker gm = GroupMaker();
    await gm.open();
    String pem = idString.substring(idString.indexOf("\n") + 1);
    int listingNum = int.parse(idString.substring(0, idString.indexOf("\n")));
    // check if the group has already been added
    Group g = await gm.getGroup(listingNum);
    if (g != null) {
      await gm.close();
      return g;
    }
    print(listingNum.toString());
    var encryptedName = jsonDecode((await http
            .post(address + '/getListingName', body: {"listingId": listingNum.toString()}))
        .body)[0].toString();
    var decrypter = new RsaKeyHelper();
    print(encryptedName);
    String name = encryptedName;
    try {
      //if the listing isn't ciphertext, itll fail and as a result it won't get changed
     name = decrypter.decrypt(encryptedName, decrypter.parsePrivateKeyFromPem(pem));
    } catch(e, i){

    }
    var group = Group(listingNum, "", name, pem, "");
    await gm.insert(group);
    syncNums(listingNum); //this sets the timestamp  appropriately and pulls numbers
    await gm.close();
    return group;
  }

  static void registerGroup(String groupName, bool isPublic) async {
    //todo gen key, make api calls
    var rsaHelper = new RsaKeyHelper();
    var createKeys = rsaHelper.generateKeyPair();
    var deleteKeys = rsaHelper.generateKeyPair();
    String pubkey = "";
    var name = groupName;
    if (isPublic) {
      pubkey = rsaHelper.encodePrivateKeyToPem(
          createKeys.privateKey); // I swear this makes more sense in context
    } else{
      name = rsaHelper.encrypt(groupName, createKeys.publicKey);
    }
    var response = await http.post(address + "/makeListing", body: {
      'key': rsaHelper.encodePublicKeyToPem(createKeys.publicKey),
      'delKey': rsaHelper.encodePrivateKeyToPem(deleteKeys.privateKey),
      'name': name,
      'pubkey': pubkey
    });
    var listing = jsonDecode(response.body);
    String deleteKey = rsaHelper.encodePublicKeyToPem(deleteKeys.publicKey);
    String privkey = rsaHelper.encodePrivateKeyToPem(createKeys.privateKey);
    pubkey = rsaHelper.encodePublicKeyToPem(createKeys.publicKey);
    Group newGroup = new Group(listing, deleteKey, groupName, privkey, pubkey);
    GroupMaker maker = new GroupMaker();
    await maker.open();
    await maker.insert(newGroup);
  }

  static void batchSyncNums() async {
    var results = Map<String, int>();
    for (var row in await getGroups()) {
      //jsonEncode fails badly on maps w/o string keys, no idea why this isn't implemented already
      results[row["id"].toString()] = row["timestamp"];
    }
    var changes = jsonDecode((await http.post(
            address + "/batchGetListingAfterTime",
            body: {"updates": jsonEncode(results)}))
        .body);
    print(changes);
    var gm = new GroupMaker();
    await gm.open();
    var lm = new ListingMaker();
    await lm.open();
    var decryptor = RsaKeyHelper();
      if (!await Permission.contacts.isGranted && !await Permission.contacts.request().isGranted){
        return;
      }
      changes.forEach((num, encryptedPhoneNums) async {
      if (encryptedPhoneNums.isNotEmpty) {
        Group group = await gm.getGroup(int.parse(num));
        var privKey = decryptor.parsePrivateKeyFromPem(group.privkey);
        for (var encryptedNumber in encryptedPhoneNums) {
          var decryptedNumber = decryptor.decrypt(encryptedNumber[0], privKey);
          var decryptedName = decryptor.decrypt(encryptedNumber[1],privKey);
          lm.insert(Listing(group.id,decryptedNumber,decryptedName));
          var contactsWithNum = await ContactsService.getContactsForPhone(
              decryptedNumber,
              withThumbnails: false);
          if (contactsWithNum.isEmpty) {
            ContactsService.addContact(new Contact(
                prefix: group.name + ":",
                givenName: decryptedName,
                familyName: " ",
                phones: [new Item(label: "home", value: decryptedNumber)]));
          } else {
            for (var contact in contactsWithNum) {
              if (contact.prefix != null) {
                if (!contact.prefix.contains(group.name + ": ")) {
                  contact.prefix = group.name + ": " + contact.prefix;
                }
              } else {
                contact.prefix = group.name + ": ";
              }
              ContactsService.updateContact(contact);
            }
          }
        }
        group.timestamp = DateTime.now().millisecondsSinceEpoch;
        gm.update(group); //get that updated asap
      }
    });
  }

  static void syncNums(int id) async {
    var gm = new GroupMaker();
    await gm.open();
    var lm = new ListingMaker();
    await lm.open();
    var group = await gm.getGroup(id);
    var response = await http.post(address + "/getListingAfterTime", body: {
      "listingId": id.toString(),
      "timestamp": group.timestamp.toString()
    });
    group.timestamp = DateTime.now().millisecondsSinceEpoch;
    gm.update(group); //get that updated asap
    var numbers = jsonDecode(response.body);
    var decryptor = RsaKeyHelper();
    var privKey = decryptor.parsePrivateKeyFromPem(group.privkey);
    if (await Permission.contacts.isGranted ||
        await Permission.contacts.request().isGranted) {
      //we use the ||'s feature to automatically skip if the first one returns true to branch automatically
      for (var encryptedNumber in numbers) {
        var decryptedNumber = decryptor.decrypt(encryptedNumber[0], privKey);
        var decryptedName = decryptor.decrypt(encryptedNumber[1],privKey);
        lm.insert(Listing(group.id,decryptedNumber,decryptedName));
        var contactsWithNum = await ContactsService.getContactsForPhone(
            decryptedNumber,
            withThumbnails: false);
        if (contactsWithNum.isEmpty) {
          ContactsService.addContact(new Contact(
              prefix: group.name + ":",
              givenName: decryptedName,
              familyName: " ",
              phones: [new Item(label: "home", value: decryptedNumber)]));
        } else {
          for (var contact in contactsWithNum) {
            if (contact.prefix != null) {
              if (!contact.prefix.contains(group.name + ": ")) {
                contact.prefix = group.name + ": " + contact.prefix;
              }
            } else {
              contact.prefix = group.name + ": ";
            }
            ContactsService.updateContact(contact);
          }
        }
      }
    }
  }

  static void hardSyncNums(int id) async {
    GroupMaker gm = GroupMaker();
    await gm.open();
    var group = await gm.getGroup(id);
    gm.close();
    var lm = ListingMaker();
    await lm.open();
    var maps = await lm.getListings(id);
    if (await Permission.contacts.isGranted ||
        await Permission.contacts.request().isGranted) {
      //we use the ||'s feature to automatically skip if the first one returns true to branch automatically
      for (var map in maps) {
        var decryptedNumber = map.phoneNum;
        var contactsWithNum = await ContactsService.getContactsForPhone(
            decryptedNumber,
            withThumbnails: false);
        if (contactsWithNum.isEmpty) {
          ContactsService.addContact(new Contact(
              prefix: group.name + ":",
              givenName: map.name,
              familyName: " ",
              phones: [new Item(label: "home", value: decryptedNumber)]));
        } else {
          for (var contact in contactsWithNum) {
            if (contact.prefix != null) {
              if (!contact.prefix.contains(group.name + ": ")) {
                contact.prefix = group.name + ": " + contact.prefix;
              }
            } else {
              contact.prefix = group.name + ": ";
            }
            ContactsService.updateContact(contact);
          }
        }
      }
    }
    await lm.close();
    syncNums(id);
  }
}

//taken from https://gist.github.com/proteye/982d9991922276ccfb011dfc55443d74
// major props to them for doing encryption work i do not understand
List<int> decodePEM(String pem) {
  var startsWith = [
    "-----BEGIN PUBLIC KEY-----",
    "-----BEGIN PRIVATE KEY-----",
    "-----BEGIN PGP PUBLIC KEY BLOCK-----\r\nVersion: React-Native-OpenPGP.js 0.1\r\nComment: http://openpgpjs.org\r\n\r\n",
    "-----BEGIN PGP PRIVATE KEY BLOCK-----\r\nVersion: React-Native-OpenPGP.js 0.1\r\nComment: http://openpgpjs.org\r\n\r\n",
  ];
  var endsWith = [
    "-----END PUBLIC KEY-----",
    "-----END PRIVATE KEY-----",
    "-----END PGP PUBLIC KEY BLOCK-----",
    "-----END PGP PRIVATE KEY BLOCK-----",
  ];
  bool isOpenPgp = pem.indexOf('BEGIN PGP') != -1;

  for (var s in startsWith) {
    if (pem.startsWith(s)) {
      pem = pem.substring(s.length);
    }
  }

  for (var s in endsWith) {
    if (pem.endsWith(s)) {
      pem = pem.substring(0, pem.length - s.length);
    }
  }

  if (isOpenPgp) {
    var index = pem.indexOf('\r\n');
    pem = pem.substring(0, index);
  }

  pem = pem.replaceAll('\n', '');
  pem = pem.replaceAll('\r', '');

  return base64.decode(pem);
}

class RsaKeyHelper {
  AsymmetricKeyPair<PublicKey, PrivateKey> generateKeyPair() {
    var keyParams =
        new RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 12);

    var secureRandom = new FortunaRandom();
    var random = new Random.secure();
    List<int> seeds = [];
    for (int i = 0; i < 32; i++) {
      seeds.add(random.nextInt(255));
    }
    secureRandom.seed(new KeyParameter(new Uint8List.fromList(seeds)));

    var rngParams = new ParametersWithRandom(keyParams, secureRandom);
    var k = new RSAKeyGenerator();
    k.init(rngParams);
    return k.generateKeyPair();
  }

  String encrypt(String plaintext, RSAPublicKey publicKey) {
    var cipher = OAEPEncoding(RSAEngine())
      ..init(true, new PublicKeyParameter<RSAPublicKey>(publicKey));
    var cipherText =
        cipher.process(new Uint8List.fromList(plaintext.codeUnits));

    return base64.encode(cipherText);
  }

  String decrypt(String ciphertext, RSAPrivateKey privateKey) {
    var cipher = OAEPEncoding(RSAEngine())
      ..init(false, new PrivateKeyParameter<RSAPrivateKey>(privateKey));
    var decrypted = cipher.process(base64.decode(ciphertext));

    return utf8.decode(decrypted);
  }

  parsePublicKeyFromPem(pemString) {
    List<int> publicKeyDER = decodePEM(pemString);
    var asn1Parser = new ASN1Parser(publicKeyDER);
    var topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;
    var publicKeyBitString = topLevelSeq.elements[1];

    var publicKeyAsn = new ASN1Parser(publicKeyBitString.contentBytes());
    ASN1Sequence publicKeySeq = publicKeyAsn.nextObject();
    var modulus = publicKeySeq.elements[0] as ASN1Integer;
    var exponent = publicKeySeq.elements[1] as ASN1Integer;

    RSAPublicKey rsaPublicKey =
        RSAPublicKey(modulus.valueAsBigInteger, exponent.valueAsBigInteger);

    return rsaPublicKey;
  }

  parsePrivateKeyFromPem(pemString) {
    List<int> privateKeyDER = decodePEM(pemString);
    var asn1Parser = new ASN1Parser(privateKeyDER);
    var topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;
    var version = topLevelSeq.elements[0];
    var algorithm = topLevelSeq.elements[1];
    var privateKey = topLevelSeq.elements[2];

    asn1Parser = new ASN1Parser(privateKey.contentBytes());
    var pkSeq = asn1Parser.nextObject() as ASN1Sequence;

    version = pkSeq.elements[0];
    var modulus = pkSeq.elements[1] as ASN1Integer;
    var publicExponent = pkSeq.elements[2] as ASN1Integer;
    var privateExponent = pkSeq.elements[3] as ASN1Integer;
    var p = pkSeq.elements[4] as ASN1Integer;
    var q = pkSeq.elements[5] as ASN1Integer;
    var exp1 = pkSeq.elements[6] as ASN1Integer;
    var exp2 = pkSeq.elements[7] as ASN1Integer;
    var co = pkSeq.elements[8] as ASN1Integer;

    RSAPrivateKey rsaPrivateKey = RSAPrivateKey(
        modulus.valueAsBigInteger,
        privateExponent.valueAsBigInteger,
        p.valueAsBigInteger,
        q.valueAsBigInteger);

    return rsaPrivateKey;
  }

  encodePublicKeyToPem(RSAPublicKey publicKey) {
    var algorithmSeq = new ASN1Sequence();
    var algorithmAsn1Obj = new ASN1Object.fromBytes(Uint8List.fromList(
        [0x6, 0x9, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0xd, 0x1, 0x1, 0x1]));
    var paramsAsn1Obj =
        new ASN1Object.fromBytes(Uint8List.fromList([0x5, 0x0]));
    algorithmSeq.add(algorithmAsn1Obj);
    algorithmSeq.add(paramsAsn1Obj);

    var publicKeySeq = new ASN1Sequence();
    publicKeySeq.add(ASN1Integer(publicKey.modulus));
    publicKeySeq.add(ASN1Integer(publicKey.exponent));
    var publicKeySeqBitString =
        new ASN1BitString(Uint8List.fromList(publicKeySeq.encodedBytes));

    var topLevelSeq = new ASN1Sequence();
    topLevelSeq.add(algorithmSeq);
    topLevelSeq.add(publicKeySeqBitString);
    var dataBase64 = base64.encode(topLevelSeq.encodedBytes);

    return """-----BEGIN PUBLIC KEY-----\r\n$dataBase64\r\n-----END PUBLIC KEY-----""";
  }

  encodePrivateKeyToPem(RSAPrivateKey privateKey) {
    var version = ASN1Integer(BigInt.from(0));

    var algorithmSeq = new ASN1Sequence();
    var algorithmAsn1Obj = new ASN1Object.fromBytes(Uint8List.fromList(
        [0x6, 0x9, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0xd, 0x1, 0x1, 0x1]));
    var paramsAsn1Obj =
        new ASN1Object.fromBytes(Uint8List.fromList([0x5, 0x0]));
    algorithmSeq.add(algorithmAsn1Obj);
    algorithmSeq.add(paramsAsn1Obj);

    var privateKeySeq = new ASN1Sequence();
    var modulus = ASN1Integer(privateKey.n);
    var publicExponent = ASN1Integer(BigInt.parse('65537'));
    var privateExponent = ASN1Integer(privateKey.privateExponent);
    var p = ASN1Integer(privateKey.p);
    var q = ASN1Integer(privateKey.q);
    var dP = privateKey.privateExponent % (privateKey.p - BigInt.from(1));
    var exp1 = ASN1Integer(dP);
    var dQ = privateKey.privateExponent % (privateKey.q - BigInt.from(1));
    var exp2 = ASN1Integer(dQ);
    var iQ = privateKey.q.modInverse(privateKey.p);
    var co = ASN1Integer(iQ);

    privateKeySeq.add(version);
    privateKeySeq.add(modulus);
    privateKeySeq.add(publicExponent);
    privateKeySeq.add(privateExponent);
    privateKeySeq.add(p);
    privateKeySeq.add(q);
    privateKeySeq.add(exp1);
    privateKeySeq.add(exp2);
    privateKeySeq.add(co);
    var publicKeySeqOctetString =
        new ASN1OctetString(Uint8List.fromList(privateKeySeq.encodedBytes));

    var topLevelSeq = new ASN1Sequence();
    topLevelSeq.add(version);
    topLevelSeq.add(algorithmSeq);
    topLevelSeq.add(publicKeySeqOctetString);
    var dataBase64 = base64.encode(topLevelSeq.encodedBytes);

    return """-----BEGIN PRIVATE KEY-----\r\n$dataBase64\r\n-----END PRIVATE KEY-----""";
  }
}
