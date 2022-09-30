import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:recordtest/pages/Homescreen.dart';
import 'package:http/http.dart' as http;

class Recordingscreen extends StatefulWidget {
  const Recordingscreen({Key? key}) : super(key: key);

  @override
  State<Recordingscreen> createState() => _RecordingscreenState();
}

class _RecordingscreenState extends State<Recordingscreen> {
  final recorder = FlutterSoundRecorder();
  bool isRecorderReady = false;
  final recorder2 = Record();
  bool isComplete = false;
  bool isRecording = false;
  final record = Record();
  var deliveryId;
  BuildContext? gContext;
  var buttonIcon = Icons.mic;
  var buttonColor = Color.fromARGB(255, 34, 141, 203);
  bool waitingAliceResponse = false;

  final audioplayer = AudioPlayer();
  bool isplaying = false;
  Duration playduration = Duration.zero;
  Duration position = Duration.zero;

  String formatTime(Duration duartion) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duartion.inHours);
    final minutes = twoDigits(duartion.inMinutes.remainder(50));
    final seconds = twoDigits(duartion.inSeconds.remainder(60));

    return [
      if (duartion.inHours > 0) hours,
      minutes,
      seconds,
    ].join(':');
  }

  @override
  void disposeAudioplayer() {
    audioplayer.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    recorder.closeRecorder();
    recorder2.dispose();
    super.dispose();
  }

  Future<String> EndSession() async {
    var response = await http.post(
      Uri.https('iic-project.herokuapp.com', '/api/v1/endSession'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode(
        {
          "delivery": true,
        },
      ),
    );

    if (response.statusCode == 200) {
      return response.body;
    } else {
      return 'failure';
    }
  }

  Future<String> sendAudio(String audio) async {
    for (int i = 0; i < audio.length; i += 1000) {
      if (i + 1000 > audio.length) {
        print(audio.substring(i, audio.length));
      } else {
        print(audio.substring(i, i + 1000));
      }
    }

    try {
      var response = await http.post(
          Uri.https('iic-delivery.mybluemix.net', '/api/v1/sendAudio'),
          headers: {
            'Content-Type': 'application/json',
          },
          body: jsonEncode({"audioEncoded": audio, "delivery": true}));
      var data = jsonDecode(response.body) as Map<String, dynamic>;
      var chatbotResponse = data['encodedAudio'].toString();
      var orderId = data['orderId'];

      print("========WATSON======");
      print("Google: " + data['transcription'].toString());
      print("Alice: " + data['obj'].toString());

      orderId = orderId == "" ? "." : orderId;

      // if the it is done the order Id == null
      orderId = orderId == null ? data['obj']['orderId'] : orderId;

      print("OrderId: $orderId");

      if (response.statusCode == 200) {
        return '$orderId $chatbotResponse';
      } else {
        return '. $chatbotResponse'; // the dot means that the orderId is null
      }
    } catch (e) {
      print("EXCEPTION");
      print(e);
      return "failure";
    }
  }

  void ShowMessage(BuildContext context) {
    final alert = AlertDialog(
      title: Text(
        "شكرا لتعاملكم معنا",
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: Text("من فضلك انتظر الرد"),
    );

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  Future<bool> checkPermission() async {
    if (!await Permission.microphone.isGranted) {
      PermissionStatus status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        return false;
      }
    }
    return true;
  }

  void startRecord() async {
    bool hasPermission = await checkPermission();
    if (hasPermission) {
      isComplete = false;
      String recordFilePath = await getFilePath();
      // RecordMp3.instance.start(recordFilePath, (err) {
      //   print(err);
      // });
      // print(recordFilePath);
      await record.start(
          path: recordFilePath,
          encoder: AudioEncoder.amrNb, // by default
          bitRate: 128000, // by default
          samplingRate: 8000, // by default
          numChannels: 1);
    } else {
      print("You don't have permissions");
    }
  }

  // We will loop to get the response of the resident until he respondes or for 5 mintues
  getResidentResponse(String deliveryId) async {
    try {
      print("Order ID: $deliveryId");

      // TODO: wait for 5 min
      while (true) {
        await Future.delayed(const Duration(seconds: 5));

        var response = await http.post(
            Uri.https('iic-delivery.mybluemix.net', '/api/v1/checkDelivery'),
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({"orderId": deliveryId, "delivery": true}));

        if (response.body == null || response.statusCode != 200) {
          print("ERROR: error getting response from Resident");
          continue;
        } else {
          var audioEncoded = response.body;

          print("============Resident Response===========");
          print(audioEncoded);

          if (audioEncoded.isNotEmpty) {
            play(audioEncoded);

            break;
          }
        }
      }
    } catch (err) {
      print("Error: " + err.toString());
    }
  }

  void stopRecord() async {
    setState(() {
      waitingAliceResponse = true;
    });

    await record.stop();

    var audioFile = File(await getFilePath());
    print("DONE");
    List<int> fileBytes = audioFile.readAsBytesSync();
    String base64String = base64Encode(fileBytes);
    play(base64String);
    // ShowMessage(context);
    var res = await sendAudio(base64String);
    print("Middleware Res: $res");

    if (res != 'failure') {
      var audioBase64 = res.split(" ")[1];

      play(audioBase64);

      // show message to user to make him wait for the response of the reisdnet

      deliveryId = res.split(" ")[0];

      print("Delivery ID: $deliveryId");

      if (deliveryId != "." && deliveryId != null) {
        // get the response of the resident
        ShowMessage(gContext!);
        await getResidentResponse(deliveryId);
      }

      deliveryId = ".";
    }

    setState(() {
      waitingAliceResponse = false;
      isRecording = false;

      buttonIcon = Icons.mic;
      buttonColor = Color.fromARGB(255, 34, 141, 203);
    });
  }

  String? recordFilePath;

  void play(String base64Audio) async {
    print("RES");
    try {
      Uint8List src = base64Decode(base64Audio);
      audioplayer.play(BytesSource(src));
    } catch (e) {
      print("========================");
      print(e);
    }
  }

  Future<String> getFilePath() async {
    Directory storageDirectory = await getApplicationDocumentsDirectory();
    String sdPath = "${storageDirectory.path}/record";
    var d = Directory(sdPath);
    if (!d.existsSync()) {
      d.createSync(recursive: true);
    }
    return "$sdPath/test.amr";
  }

  bool _isloading = false;
  @override
  Widget build(BuildContext context) {
    gContext = context;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          "",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Color.fromARGB(255, 0, 144, 201),
        automaticallyImplyLeading: false,
        leadingWidth: 100,
        elevation: 0,
        leading: ElevatedButton.icon(
          onPressed: () async {
            var statues = await EndSession();
            if (statues == 'failure') {
              print('failed');
            } else {
              print(statues);
              Navigator.push(context,
                  MaterialPageRoute(builder: (context) => Homescreen()));
            }
            ;
          },
          icon: const Icon(Icons.arrow_left_sharp),
          label: const Text('الرجوع'),
          style: ElevatedButton.styleFrom(
              elevation: 0, primary: Colors.transparent),
        ),
      ),
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Center(
          child: Stack(
            children: [
              Container(
                height: double.infinity,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.fromARGB(255, 0, 144, 201),
                      Color.fromARGB(255, 103, 204, 255),
                      Color.fromARGB(252, 201, 229, 255),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(right: 20, left: 20),
                  child: SingleChildScrollView(
                    physics: BouncingScrollPhysics(),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 30,
                        ),
                        Center(
                          child: Text(
                            "سجل طلب  التوصيل",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 20,
                        ),
                        Center(
                          child: Text(
                            "من فضلك سجل اسم المطعم و رقم العقار المتوجه اليه",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 60,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 25),
                          child: Container(
                            width: 250,
                            height: 250,
                            child: ElevatedButton(
                                child: Icon(
                                  buttonIcon,
                                  size: 100,
                                ),
                                style: ElevatedButton.styleFrom(
                                  elevation: 20,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(200),
                                  ),
                                  primary: buttonColor,
                                  padding: EdgeInsets.all(30),
                                ),
                                onPressed: !waitingAliceResponse
                                    ? () async {
                                        if (!isRecording) {
                                          setState(() {
                                            buttonColor = const Color.fromARGB(
                                                255, 220, 41, 25);
                                            buttonIcon = Icons.square;

                                            isRecording = true;
                                          });
                                          startRecord();
                                        } else {
                                          setState(() {
                                            buttonColor = const Color.fromARGB(
                                                255, 159, 159, 159);
                                            buttonIcon = Icons.mic_off;
                                          });
                                          stopRecord();
                                        }
                                      }
                                    : null),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
