import 'dart:convert';
import 'package:fast_rsa/model/bridge.pbenum.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:pointycastle/export.dart';
import 'package:pointycastle/random/fortuna_random.dart';
import 'package:http/http.dart' as http;
import 'package:asn1lib/asn1lib.dart';
import 'package:CallLock/databaseStuff.dart';
import 'package:fast_rsa/rsa.dart';
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

  static void registerListing(int listingNum, String encryptedNumber, String encryptedName, String key) async {
    await http.post(address + "/addNumber", body: {
      "listingId": listingNum.toString(),
      "encryptedPhoneNumber": encryptedNumber,
      "encryptedName" : encryptedName,
      "key" : key
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
    return response;
  }
  static Future<Group> pullGroup(String idString) async {
    print(1);
    GroupMaker gm = GroupMaker();
    print(2);
    await gm.open();
    print(3);
    String pem = idString.substring(idString.indexOf("\n") + 1);
    int listingNum = int.parse(idString.substring(0, idString.indexOf("\n")));
    // check if the group has already been added
    Group g = await gm.getGroup(listingNum);
    if (g != null) {
      await gm.close();
      return g;
    }
    var encryptedName = jsonDecode((await http
            .post(address + '/getListingName', body: {"listingId": listingNum.toString()}))
        .body);
    var key = await RSA.decryptOAEPBytes(
            base64Decode(encryptedName[1]),
            "",
            Hash.HASH_SHA256,
            pem);
    print(key);
    String name = String.fromCharCodes(base64Decode(encryptedName[0]));
    if(key.lengthInBytes!=0){
      name = AesHelper.decrypt(key, encryptedName[0]);
    }
    var group = Group(listingNum, "", name, pem, "");
    await gm.insert(group);
    syncNums(listingNum); //this sets the timestamp  appropriately and pulls numbers
    await gm.close();
    return group;
  }

  static void registerGroup(String groupName, bool isPublic) async {
    //todo gen key, make api calls
    var createKeys = await RSA.generate(2048);
    var deleteKeys = await RSA.generate(2048);
    var key = AesHelper.deriveKey(groupName + DateTime.now().toString());
    var encryptedKey = "";
    String pubkey = "";
    var name = groupName;
    if (isPublic) {
      pubkey = await RSA.convertPrivateKeyToPKCS8(createKeys.privateKey); // I swear this makes more sense in context
    } else{
      name = AesHelper.encrypt(key, name);
      encryptedKey = base64Encode(await RSA.encryptOAEPBytes(key,"",Hash.HASH_SHA256, createKeys.publicKey));
    }
    var response = await http.post(address + "/makeListing", body: {
      'key': encryptedKey,
      'delKey': await RSA.convertPrivateKeyToPKCS8(deleteKeys.privateKey),
      'name': name,
      'pubkey': pubkey
    });
    var listing = jsonDecode(response.body);
    String deleteKey = await RSA.convertPublicKeyToPKCS1(deleteKeys.publicKey);
    String privkey = await RSA.convertPrivateKeyToPKCS8(createKeys.privateKey);
    pubkey = jsonEncode(await RSA.convertPublicKeyToPKCS1(createKeys.publicKey));
    print(pubkey);
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
    var gm = new GroupMaker();
    await gm.open();
    var lm = new ListingMaker();
    await lm.open();
      if (!await Permission.contacts.isGranted && !await Permission.contacts.request().isGranted){
        return;
      }
      changes.forEach((num, encryptedPhoneNums) async {
      if (encryptedPhoneNums.isNotEmpty) {
        Group group = await gm.getGroup(int.parse(num));
        for (var encryptedNumber in encryptedPhoneNums) {
          Uint8List key = await RSA.decryptOAEPBytes(base64Decode(encryptedNumber[2]),"",Hash.HASH_SHA256, group.privkey);
          var decryptedNumber = AesHelper.decrypt(key, encryptedNumber[0]);
          var decryptedName = AesHelper.decrypt(key, encryptedNumber[1]);
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
    if (await Permission.contacts.isGranted ||
        await Permission.contacts.request().isGranted) {
      //we use the ||'s feature to automatically skip if the first one returns true to branch automatically
      for (var encryptedNumber in numbers) {
        Uint8List key = await RSA.decryptOAEPBytes(base64Decode(encryptedNumber[2]),"",Hash.HASH_SHA256, group.privkey);
        print(key);
        var decryptedNumber = AesHelper.decrypt(key, encryptedNumber[0]);
        print(decryptedNumber);
        var decryptedName = AesHelper.decrypt(key, encryptedNumber[1]);
        print(decryptedName);
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
const KEY_SIZE = 32; // 32 byte key for AES-256
const ITERATION_COUNT = 1000;
// from gist.github.com/ethanliew/a0f135eabaade337d62f05ec0a97d587
class AesHelper {
  static const CBC_MODE = 'CBC';
  static const CFB_MODE = 'CFB';

  static Uint8List deriveKey(dynamic password,
      {String salt = '',
        int iterationCount = ITERATION_COUNT,
        int derivedKeyLength = KEY_SIZE}) {
    if (password == null || password.isEmpty) {
      throw new ArgumentError('password must not be empty');
    }

    if (password is String) {
      password = createUint8ListFromString(password);
    }

    Uint8List saltBytes = createUint8ListFromString(salt);
    Pbkdf2Parameters params =
    new Pbkdf2Parameters(saltBytes, iterationCount, derivedKeyLength);
    KeyDerivator keyDerivator =
    new PBKDF2KeyDerivator(new HMac(new SHA256Digest(), 64));
    keyDerivator.init(params);

    return keyDerivator.process(password);
  }

  static Uint8List pad(Uint8List src, int blockSize) {
    var pad = new PKCS7Padding();
    pad.init(null);

    int padLength = blockSize - (src.length % blockSize);
    var out = new Uint8List(src.length + padLength)..setAll(0, src);
    pad.addPadding(out, src.length);

    return out;
  }

  static Uint8List unpad(Uint8List src) {
    var pad = new PKCS7Padding();
    pad.init(null);

    int padLength = pad.padCount(src);
    int len = src.length - padLength;

    return new Uint8List(len)..setRange(0, len, src);
  }

  static String encrypt(Uint8List derivedKey, String plaintext,
      {String mode = CBC_MODE}) {
    KeyParameter keyParam = new KeyParameter(derivedKey);
    BlockCipher aes = new AESFastEngine();

    var rnd = FortunaRandom();
    rnd.seed(keyParam);
    Uint8List iv = rnd.nextBytes(aes.blockSize);

    BlockCipher cipher;
    ParametersWithIV params = new ParametersWithIV(keyParam, iv);
    switch (mode) {
      case CBC_MODE:
        cipher = new CBCBlockCipher(aes);
        break;
      case CFB_MODE:
        cipher = new CFBBlockCipher(aes, aes.blockSize);
        break;
      default:
        throw new ArgumentError('incorrect value of the "mode" parameter');
        break;
    }
    cipher.init(true, params);

    Uint8List textBytes = createUint8ListFromString(plaintext);
    Uint8List paddedText = pad(textBytes, aes.blockSize);
    Uint8List cipherBytes = _processBlocks(cipher, paddedText);
    Uint8List cipherIvBytes = new Uint8List(cipherBytes.length + iv.length)
      ..setAll(0, iv)
      ..setAll(iv.length, cipherBytes);

    return base64.encode(cipherIvBytes);
  }

  static String decrypt(Uint8List derivedKey, String ciphertext,
      {String mode = CBC_MODE}) {
    KeyParameter keyParam = new KeyParameter(derivedKey);
    BlockCipher aes = new AESFastEngine();

    Uint8List cipherIvBytes = base64.decode(ciphertext);
    Uint8List iv = new Uint8List(aes.blockSize)
      ..setRange(0, aes.blockSize, cipherIvBytes);

    BlockCipher cipher;
    ParametersWithIV params = new ParametersWithIV(keyParam, iv);
    switch (mode) {
      case CBC_MODE:
        cipher = new CBCBlockCipher(aes);
        break;
      case CFB_MODE:
        cipher = new CFBBlockCipher(aes, aes.blockSize);
        break;
      default:
        throw new ArgumentError('incorrect value of the "mode" parameter');
        break;
    }
    cipher.init(false, params);

    int cipherLen = cipherIvBytes.length - aes.blockSize;
    Uint8List cipherBytes = new Uint8List(cipherLen)
      ..setRange(0, cipherLen, cipherIvBytes, aes.blockSize);
    Uint8List paddedText = _processBlocks(cipher, cipherBytes);
    Uint8List textBytes = unpad(paddedText);

    return new String.fromCharCodes(textBytes);
  }

  static Uint8List _processBlocks(BlockCipher cipher, Uint8List inp) {
    var out = new Uint8List(inp.lengthInBytes);

    for (var offset = 0; offset < inp.lengthInBytes;) {
      var len = cipher.processBlock(inp, offset, out, offset);
      offset += len;
    }

    return out;
  }
}
Uint8List createUint8ListFromString(String s) {
  var ret = new Uint8List(s.length);
  for (var i = 0; i < s.length; i++) {
    ret[i] = s.codeUnitAt(i);
  }
  return ret;
}

Uint8List createUint8ListFromHexString(String hex) {
  var result = new Uint8List(hex.length ~/ 2);
  for (var i = 0; i < hex.length; i += 2) {
    var num = hex.substring(i, i + 2);
    var byte = int.parse(num, radix: 16);
    result[i ~/ 2] = byte;
  }
  return result;
}

Uint8List createUint8ListFromSequentialNumbers(int len) {
  var ret = new Uint8List(len);
  for (var i = 0; i < len; i++) {
    ret[i] = i;
  }
  return ret;
}

String formatBytesAsHexString(Uint8List bytes) {
  var result = new StringBuffer();
  for (var i = 0; i < bytes.lengthInBytes; i++) {
    var part = bytes[i];
    result.write('${part < 16 ? '0' : ''}${part.toRadixString(16)}');
  }
  return result.toString();
}


