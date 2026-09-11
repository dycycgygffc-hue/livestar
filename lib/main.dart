import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

void main() {
  if (Api.base.isEmpty) {
    throw StateError('API_URL is required. Build with --dart-define=API_URL=https://api.example.com');
  }
  runApp(const LiveStarApp());
}

const pink = Color(0xFFFF20C8);
const purple = Color(0xFF7B2CFF);
const bg = Color(0xFF060719);
const card = Color(0xFF11152C);
const gold = Color(0xFFFFC83D);
class Api {
  // Release builds must provide API_URL via --dart-define.
  static const base = String.fromEnvironment('API_URL', defaultValue: '');
  static String? token;
  static Map<String,dynamic>? me;
  static Future<Map<String,dynamic>> requestOtp(String phone) async {
    final r=await http.post(Uri.parse('$base/auth/request-otp'),headers:{'Content-Type':'application/json'},body:jsonEncode({'phone':phone}));
    return _json(r);
  }
  static Future<Map<String,dynamic>> verifyOtp(String phone,String code) async {
    final r=await http.post(Uri.parse('$base/auth/verify-otp'),headers:{'Content-Type':'application/json'},body:jsonEncode({'phone':phone,'code':code}));
    final d=_json(r); token=d['token']; me=Map<String,dynamic>.from(d['user']); return d;
  }
  static Future<Map<String,dynamic>> profile() async {
    final r=await http.get(Uri.parse('$base/me'),headers:_headers()); final d=_json(r); me=d; return d;
  }
  static Future<Map<String,dynamic>> transfer(String to,int coins) async {
    final r=await http.post(Uri.parse('$base/wallet/transfer'),headers:_headers(),body:jsonEncode({'toPublicId':to,'coins':coins})); return _json(r);
  }
  static Future<List<dynamic>> roomMembers(String roomId) async {
    final r=await http.get(Uri.parse('$base/rooms/$roomId/members'),headers:_headers()); return _json(r) as List<dynamic>;
  }
  static Future<List<dynamic>> roomSeats(String roomId) async { final r=await http.get(Uri.parse('$base/rooms/$roomId/seats'),headers:_headers()); return _json(r) as List<dynamic>; }
  static Future<List<dynamic>> seatRequests(String roomId) async { final r=await http.get(Uri.parse('$base/rooms/$roomId/seat-requests'),headers:_headers()); return _json(r) as List<dynamic>; }
  static Future<void> seatRequest(String roomId) async { final r=await http.post(Uri.parse('$base/rooms/$roomId/seat-request'),headers:_headers()); _json(r); }
  static Future<void> seatResponse(String roomId,int requestId,String action) async { final r=await http.post(Uri.parse('$base/rooms/$roomId/seat-response'),headers:_headers(),body:jsonEncode({'requestId':requestId,'action':action})); _json(r); }
  static Future<void> seatLeave(String roomId) async { final r=await http.post(Uri.parse('$base/rooms/$roomId/seat-leave'),headers:_headers()); _json(r); }
  static Future<void> moderate(String roomId,String action,String userId,{String reason=''}) async {
    final r=await http.post(Uri.parse('$base/rooms/$roomId/moderation'),headers:_headers(),body:jsonEncode({'action':action,'userId':userId,'reason':reason})); _json(r);
  }
  static Future<List<dynamic>> gifts() async { final r=await http.get(Uri.parse('$base/gifts'),headers:_headers()); return _json(r) as List<dynamic>; }
  static Future<Map<String,dynamic>> sendGift(String roomId,int giftId,String receiverPublicId) async { final r=await http.post(Uri.parse('$base/rooms/$roomId/gifts'),headers:_headers(),body:jsonEncode({'giftId':giftId,'receiverPublicId':receiverPublicId})); return _json(r); }
  static Future<List<dynamic>> transactions() async {
    final r=await http.get(Uri.parse('$base/transactions'),headers:_headers()); return _json(r) as List<dynamic>;
  }
  static Future<Map<String,dynamic>> social(String publicId) async { final r=await http.get(Uri.parse('$base/users/$publicId/social'),headers:_headers()); return Map<String,dynamic>.from(_json(r)); }
  static Future<Map<String,dynamic>> follow(String publicId) async { final r=await http.post(Uri.parse('$base/users/$publicId/follow'),headers:_headers()); return Map<String,dynamic>.from(_json(r)); }
  static Future<Map<String,dynamic>> unfollow(String publicId) async { final r=await http.delete(Uri.parse('$base/users/$publicId/follow'),headers:_headers()); return Map<String,dynamic>.from(_json(r)); }
  static Future<List<dynamic>> leaderboard() async { final r=await http.get(Uri.parse('$base/leaderboard/users'),headers:_headers()); return _json(r) as List<dynamic>; }
  static Future<Map<String,dynamic>> vipStatus() async { final r=await http.get(Uri.parse('$base/vip/status'),headers:_headers()); return Map<String,dynamic>.from(_json(r)); }
  static Future<Map<String,dynamic>> renewVip(int level) async { final r=await http.post(Uri.parse('$base/vip/renew'),headers:_headers(),body:jsonEncode({'level':level})); return Map<String,dynamic>.from(_json(r)); }
  static Future<List<dynamic>> stickers() async { final r=await http.get(Uri.parse('$base/chat/stickers'),headers:_headers()); return _json(r) as List<dynamic>; }
  static Future<Map<String,dynamic>> likeRoom(String roomId) async { final r=await http.post(Uri.parse('$base/rooms/$roomId/like'),headers:_headers()); return Map<String,dynamic>.from(_json(r)); }
  static Future<Map<String,dynamic>> roomStats(String roomId) async { final r=await http.get(Uri.parse('$base/rooms/$roomId/stats'),headers:_headers()); return Map<String,dynamic>.from(_json(r)); }
  static Map<String,String> _headers()=>{'Content-Type':'application/json','Authorization':'Bearer ${token??''}'};
  static dynamic _json(http.Response r){ final d=jsonDecode(r.body); if(r.statusCode<200||r.statusCode>=300) throw Exception(d['error']??'REQUEST_FAILED'); return d; }
}


class LiveStarApp extends StatelessWidget {
  const LiveStarApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'LiveStar',
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(seedColor: purple, brightness: Brightness.dark),
      fontFamily: 'Arial',
    ),
    home: const LoginPage(),
  );
}

class GButton extends StatelessWidget {
  final String text; final VoidCallback onTap;
  const GButton(this.text, this.onTap, {super.key});
  @override
  Widget build(BuildContext c) => InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(18),
    child: Container(
      height: 52, alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(colors: [purple, pink]),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
    ),
  );
}

class LoginPage extends StatefulWidget { const LoginPage({super.key}); @override State<LoginPage> createState()=>_LoginPageState(); }
class _LoginPageState extends State<LoginPage>{
 final phone=TextEditingController(text:'+964 '); final code=TextEditingController(); bool sent=false,loading=false; 
 Future<void> send() async { setState(()=>loading=true); try { final d=await Api.requestOtp(phone.text.trim()); setState(()=>sent=true); } catch(e){ _err(e); } finally{setState(()=>loading=false);} }
 Future<void> verify() async { setState(()=>loading=true); try { await Api.verifyOtp(phone.text.trim(),code.text.trim()); if(mounted) Navigator.pushReplacement(context,MaterialPageRoute(builder:(_)=>const Home())); } catch(e){_err(e);} finally{if(mounted)setState(()=>loading=false);} }
 void _err(Object e)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('تعذر التنفيذ: $e')));
 @override Widget build(BuildContext c)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(body:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(24),child:Column(children:[
  const Icon(Icons.stars_rounded,size:78,color:pink), const SizedBox(height:12), const Text('LiveStar',style:TextStyle(fontSize:34,fontWeight:FontWeight.w900)), const Text('عالمك للبث والدردشة والهدايا',style:TextStyle(color:Colors.white60)), const SizedBox(height:35),
  TextField(controller:phone,keyboardType:TextInputType.phone,decoration:const InputDecoration(labelText:'رقم الهاتف',hintText:'+964XXXXXXXXXX',filled:true)),
  if(sent)...[const SizedBox(height:12),TextField(controller:code,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'رمز التحقق OTP',filled:true))],
  const SizedBox(height:18), GButton(loading?'جاري التنفيذ...':(sent?'دخول إلى LiveStar':'إرسال رمز OTP'), loading?():(sent?verify:send)),
  const SizedBox(height:16), const Text('Google  •  Apple',style:TextStyle(color:Colors.white54)),
  const SizedBox(height:12), const Text('للاستخدام الحقيقي اربط مزود SMS رسمي ولا تعرض رمز OTP للمستخدم.',textAlign:TextAlign.center,style:TextStyle(fontSize:12,color:Colors.white38))
]))));
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override State<Home> createState() => _HomeState();
}
class _HomeState extends State<Home> {
  int tab = 0;
  final pages = const [Discover(), Rooms(), Wallet(), Profile()];
  @override
  Widget build(BuildContext c) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      body: pages[tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() => tab = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.groups_outlined), label: 'الغرف'),
          NavigationDestination(icon: Icon(Icons.card_giftcard), label: 'الهدايا'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'ملفي'),
        ],
      ),
    ),
  );
}

class Discover extends StatelessWidget {
  const Discover({super.key});
  @override
  Widget build(BuildContext c) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('LiveStar', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.search)),
          IconButton(onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const Notifications())), icon: const Icon(Icons.notifications_none)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(colors: [Color(0xFF42127F), Color(0xFF8D176F)]),
            ),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('عالمك يبدأ هنا ✨', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
              SizedBox(height: 7), Text('بث مباشر • غرف صوتية • دردشة • هدايا فخمة'),
            ]),
          ),
          const SizedBox(height: 20),
          const Text('الأكثر شعبية 🔥', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...['Lina','Sara','Rana','Zain'].map((n) => Card(
            color: card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: ListTile(
              leading: CircleAvatar(backgroundColor: purple, child: Text(n[0])),
              title: Text('$n  👑'),
              subtitle: const Text('بث مباشر الآن • 12.4K مشاهد'),
              trailing: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: pink),
                onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const LiveRoom())),
                child: const Text('دخول'),
              ),
            ),
          )),
        ],
      ),
    ),
  );
}

class Rooms extends StatelessWidget {
  const Rooms({super.key});
  @override Widget build(BuildContext c) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('الغرف العامة')),
      body: ListView.builder(
        padding: const EdgeInsets.all(14),
        itemCount: 8,
        itemBuilder: (_, i) => Card(
          color: card,
          child: ListTile(
            leading: CircleAvatar(backgroundColor: [pink,purple,gold,Colors.blue][i%4], child: Text('${i+1}')),
            title: Text(['غرفة الأصدقاء 👑','جلسة شباب','موسيقى ووناسة','ليلة السمر'][i%4]),
            subtitle: Text('${192-i*13} متصل • دردشة عامة'),
            trailing: const Icon(Icons.graphic_eq, color: pink),
            onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const LiveRoom())),
          ),
        ),
      ),
    ),
  );
}

class LiveRoom extends StatefulWidget {
  final String roomId;
  final String mode;
  const LiveRoom({super.key, this.roomId='RDEMO', this.mode='voice'});
  @override State<LiveRoom> createState()=>_LiveRoomState();
}

class _LiveRoomState extends State<LiveRoom>{
  WebSocketChannel? channel;
  final msg=TextEditingController();
  final List<Map<String,dynamic>> events=[];
  final Map<String,RTCPeerConnection> peers={};
  final RTCVideoRenderer localRenderer=RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer=RTCVideoRenderer();
  MediaStream? localStream;
  String? myId, hostId;
  bool connected=false, mic=true, cam=true, loadingMedia=false;
  final Map<String,Map<String,dynamic>> participants={};
  final Map<int,Map<String,dynamic>?> seats={for(int i=1;i<=20;i++) i:null};
  final List<Map<String,dynamic>> seatRequests=[];
  bool seated=false;
  Map<String,dynamic>? activeGift;
  int viewers=0, likes=0;
  final Set<String> vipIds={};

  final Map<String,dynamic> rtcConfig={
    'iceServers':[
      {'urls':['stun:stun.l.google.com:19302']},
      // Production: add your authenticated TURN server here.
    ]
  };

  @override void initState(){super.initState(); _init();}
  Future<void> _init() async {
    await localRenderer.initialize(); await remoteRenderer.initialize();
    await _connect();
  }

  Future<void> _startMedia() async {
    if(loadingMedia || localStream!=null) return;
    setState(()=>loadingMedia=true);
    try {
      localStream=await navigator.mediaDevices.getUserMedia(widget.mode=='voice' ? {'audio':true,'video':false} : {'audio':true,'video':{'facingMode':'user','width':{'ideal':720},'height':{'ideal':1280}}});
      localRenderer.srcObject=localStream;
      if(mounted) setState(()=>loadingMedia=false);
    } catch(e) {
      if(mounted){setState(()=>loadingMedia=false); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تعذر الوصول للكاميرا أو المايك')));}
    }
  }

  Future<void> _connect() async {
    await _startMedia();
    final base=Api.base.replaceFirst(RegExp(r'^http'),'ws');
    final uri=Uri.parse('$base/ws?room=${Uri.encodeComponent(widget.roomId)}&token=${Uri.encodeComponent(Api.token??'')}');
    try {
      channel=WebSocketChannel.connect(uri);
      channel!.stream.listen((raw) async {
        final d=jsonDecode(raw.toString()) as Map<String,dynamic>; if(!mounted)return;
        final type=d['type'];
        if(type=='joined'){
          viewers=(d['room']?['viewerCount'] as int?) ?? 0;
          myId=d['user']?['id']; hostId=d['room']?['hostId'];
          participants[myId??'']=Map<String,dynamic>.from(d['user']??{});
          setState(()=>connected=true);
          try { final st=await Api.roomStats(widget.roomId); likes=int.tryParse(st['likes'].toString())??0; final list=await Api.roomMembers(widget.roomId); for(final x in list) participants[x['id'].toString()]=Map<String,dynamic>.from(x); final ss=await Api.roomSeats(widget.roomId); for(final x in ss){ final n=int.tryParse(x['seat'].toString())??0; if(n>0 && x['user_id']!=null) seats[n]=Map<String,dynamic>.from(x); } } catch(_) {}
        } else if(type=='seat_request'){ seatRequests.add(Map<String,dynamic>.from(d)); if(mounted)setState((){}); } else if(type=='seat_response'){ final target=String(d['target']??''); final action=String(d['action']??''); if(action=='accept' && target.isNotEmpty){ final n=int.tryParse(d['seat'].toString())??0; if(n>0) seats[n]={'id':target,'name':d['name']??'مستخدم','seat':n}; if(target==myId) { seated=true; } } if(action=='reject'&&target==myId) seated=false; if(action=='accept') { await _negotiateAudioPeers(); } seatRequests.removeWhere((q)=>q['requestId'].toString()==d['requestId'].toString()); if(mounted)setState((){}); } else if(type=='seat_left'){ final target=String(d['target']??''); seats.updateAll((k,v)=>v!=null&&v['id']==target?null:v); if(target==myId) seated=false; if(mounted)setState((){}); } else if(type=='signal'){ await _handleSignal(d); }
        else { setState(()=>events.add(d)); if(type=='gift'){ activeGift=Map<String,dynamic>.from(d); Future.delayed(const Duration(seconds:3),(){if(mounted)setState(()=>activeGift=null);}); } if(type=='viewer_count'){ viewers=int.tryParse(d['count'].toString())??viewers; } if(type=='like_count'){ likes=int.tryParse(d['count'].toString())??likes; } if(type=='presence') { final u=Map<String,dynamic>.from(d['user']??{}); if(d['action']=='join') participants[u['id'].toString()]=u; else participants.remove(u['id'].toString()); await _handlePresence(d); } if(type=='seat_status'){ final target=String(d['target']??''); final muted=d['muted']==true; seats.updateAll((k,v){ if(v!=null && v['id']==target){ final x=Map<String,dynamic>.from(v); x['status']=muted?'muted':'occupied'; return x; } return v; }); if(target==myId && muted){ for(final t in localStream?.getAudioTracks()??[]) t.enabled=false; if(mounted)setState(()=>mic=false); } if(mounted)setState((){}); } if(type=='moderation' && d['action']=='mute' && d['target']==myId) { for(final t in localStream?.getAudioTracks()??[]) t.enabled=false; if(mounted)setState(()=>mic=false); } if(type=='moderation' && (d['action']=='kick'||d['action']=='ban') && d['target']==myId){ if(mounted) Navigator.pop(context); } }
      },onDone:(){if(mounted)setState(()=>connected=false);},onError:(_){if(mounted)setState(()=>connected=false);});
    } catch(_){if(mounted)setState(()=>connected=false);}
  }

  Future<RTCPeerConnection> _peer(String peerId) async {
    final existing=peers[peerId]; if(existing!=null) return existing;
    final pc=await createPeerConnection(rtcConfig);
    peers[peerId]=pc;
    if(localStream!=null && (myId==hostId || seated)){
      for(final track in localStream!.getTracks()) { await pc.addTrack(track,localStream!); }
    }
    pc.onIceCandidate=(candidate){
      if(candidate.candidate!=null) _send('signal',{'to':peerId,'data':{'kind':'ice','candidate':candidate.toMap()}});
    };
    pc.onTrack=(event){ if(event.streams.isNotEmpty){ remoteRenderer.srcObject=event.streams.first; if(mounted)setState((){}); } };
    pc.onConnectionState=(state){
      if(state==RTCPeerConnectionState.RTCPeerConnectionStateFailed || state==RTCPeerConnectionState.RTCPeerConnectionStateClosed){ peers.remove(peerId); }
    };
    return pc;
  }

  List<String> _activeAudioPeers() {
    final ids=<String>{};
    for(final u in seats.values) {
      final id=u?['id']?.toString();
      if(id!=null && id.isNotEmpty && id!=myId) ids.add(id);
    }
    if(hostId!=null && hostId!=myId) ids.add(hostId!);
    return ids.toList();
  }

  bool _shouldOfferTo(String peerId) {
    if(myId==hostId) return true;
    if(peerId==hostId) return true;
    if(!seated) return false;
    // Among guest seats, only one side initiates to avoid SDP offer glare.
    return (myId??'').compareTo(peerId) < 0;
  }

  Future<void> _negotiateAudioPeers() async {
    if(myId==null || (myId!=hostId && !seated)) return;
    for(final id in _activeAudioPeers()) {
      if(_shouldOfferTo(id)) { try { await _makeOffer(id); } catch(_) {} }
    }
  }

  Future<void> _makeOffer(String peerId) async {
    if(myId!=hostId && !(seated && (peerId==hostId || _shouldOfferTo(peerId)))) return;
    final pc=await _peer(peerId);
    final offer=await pc.createOffer({'offerToReceiveAudio':true,'offerToReceiveVideo':true});
    await pc.setLocalDescription(offer);
    _send('signal',{'to':peerId,'data':{'kind':'offer','sdp':offer.toMap()}});
  }

  Future<void> _handleSignal(Map<String,dynamic> d) async {
    final from=String(d['from']??''); if(from.isEmpty || from==myId) return;
    final data=Map<String,dynamic>.from(d['data']??{}); final kind=data['kind'];
    final pc=await _peer(from);
    if(kind=='offer'){
      final sdp=Map<String,dynamic>.from(data['sdp']);
      await pc.setRemoteDescription(RTCSessionDescription(sdp['sdp'],sdp['type']));
      final answer=await pc.createAnswer({'offerToReceiveAudio':true,'offerToReceiveVideo':true});
      await pc.setLocalDescription(answer);
      _send('signal',{'to':from,'data':{'kind':'answer','sdp':answer.toMap()}});
    } else if(kind=='answer'){
      final sdp=Map<String,dynamic>.from(data['sdp']);
      await pc.setRemoteDescription(RTCSessionDescription(sdp['sdp'],sdp['type']));
    } else if(kind=='ice'){
      final c=Map<String,dynamic>.from(data['candidate']);
      await pc.addCandidate(RTCIceCandidate(c['candidate'],c['sdpMid'],c['sdpMLineIndex']));
    }
  }

  void _send(String type,[Map<String,dynamic>? extra]){channel?.sink.add(jsonEncode({'type':type,...?extra}));}
  void _chat(){final t=msg.text.trim();if(t.isEmpty)return;_send('chat',{'text':t});msg.clear();}
  Future<void> _stickerSheet(BuildContext c) async {
    try { final list=await Api.stickers(); if(!mounted)return; showModalBottomSheet(context:c,backgroundColor:card,isScrollControlled:true,builder:(_)=>Directionality(textDirection:TextDirection.rtl,child:SafeArea(child:Padding(padding:const EdgeInsets.all(14),child:Column(mainAxisSize:MainAxisSize.min,children:[const Text('ملصقات متحركة ✨',style:TextStyle(fontSize:21,fontWeight:FontWeight.bold)),const SizedBox(height:12),SizedBox(height:250,child:GridView.builder(itemCount:list.length,gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:4,crossAxisSpacing:8,mainAxisSpacing:8),itemBuilder:(_,i){final st=Map<String,dynamic>.from(list[i]); final req=int.tryParse('${st['vipRequired']??0}')??0; final current=int.tryParse('${Api.me?['vipLevel']??0}')??0; final locked=current<req; return InkWell(onTap:locked?(){ScaffoldMessenger.of(c).showSnackBar(SnackBar(content:Text('يحتاج VIP $req')));}:(){Navigator.pop(c);_send('sticker',{'code':st['code']});},child:Container(decoration:BoxDecoration(color:Colors.white.withOpacity(.05),borderRadius:BorderRadius.circular(18),border:Border.all(color:locked?Colors.white10:purple.withOpacity(.5))),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[_AnimatedStickerBubble(visual:'${st['visual']}',name:'${st['name']}'),if(req>0)Text('VIP $req',style:TextStyle(fontSize:9,color:locked?Colors.white38:gold,fontWeight:FontWeight.bold))])));}))))])))); } catch(_) { if(mounted)ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content:Text('تعذر تحميل الملصقات'))); }
  }

  Future<void> _toggleMic() async {final tracks=localStream?.getAudioTracks()??[];for(final t in tracks)t.enabled=!mic;setState(()=>mic=!mic);}
  Future<void> _toggleCam() async {final tracks=localStream?.getVideoTracks()??[];for(final t in tracks)t.enabled=!cam;setState(()=>cam=!cam);}
  Future<void> _handlePresence(Map<String,dynamic> e) async { if(e['action']=='join'){ await _negotiateAudioPeers(); } }

  Future<void> _moderateSheet(BuildContext c) async {
    if(myId!=hostId) return;
    final list=participants.values.where((u)=>u['id']!=myId).toList();
    await showModalBottomSheet(context:c,backgroundColor:card,builder:(_)=>Directionality(textDirection:TextDirection.rtl,child:SafeArea(child:ListView(shrinkWrap:true,padding:const EdgeInsets.all(16),children:[
      const Text('إدارة الغرفة',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
      const SizedBox(height:10),
      if(list.isEmpty) const Padding(padding:EdgeInsets.all(20),child:Text('لا يوجد أعضاء حالياً')),
      ...list.map((u)=>Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.person)),title:Text(u['name']??'مستخدم'),subtitle:Text(u['id']??''),trailing:PopupMenuButton<String>(onSelected:(a) async { try { await Api.moderate(widget.roomId,a,u['id'].toString()); if(mounted)Navigator.pop(c); } catch(e){ if(mounted)ScaffoldMessenger.of(c).showSnackBar(SnackBar(content:Text('تعذر التنفيذ: $e'))); } },itemBuilder:(_)=>const [PopupMenuItem(value:'mute',child:Text('كتم المايك')),PopupMenuItem(value:'kick',child:Text('طرد')),PopupMenuItem(value:'ban',child:Text('حظر'))]))))
    ]))));
  }

  Future<void> _roomGiftSheet(BuildContext c) async {
    final receiver = myId==hostId ? (participants.keys.where((x)=>x!=myId).cast<String?>().firstWhere((x)=>x!=null,orElse:()=>null)) : hostId;
    if(receiver==null || receiver.isEmpty){ ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content:Text('لا يوجد مستلم متاح حالياً'))); return; }
    try {
      final gifts=await Api.gifts();
      if(!mounted)return;
      showModalBottomSheet(context:c,backgroundColor:card,isScrollControlled:true,builder:(_)=>Directionality(textDirection:TextDirection.rtl,child:SafeArea(child:Padding(padding:const EdgeInsets.all(14),child:Column(mainAxisSize:MainAxisSize.min,children:[
        const Text('أرسل هدية 🎁',style:TextStyle(fontSize:21,fontWeight:FontWeight.bold)),
        const SizedBox(height:12),
        SizedBox(height:260,child:GridView.builder(itemCount:gifts.length,gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:3,crossAxisSpacing:8,mainAxisSpacing:8),itemBuilder:(_,i){final g=Map<String,dynamic>.from(gifts[i]);return InkWell(borderRadius:BorderRadius.circular(18),onTap:() async { Navigator.pop(c); try { await Api.sendGift(widget.roomId,int.parse(g['id'].toString()),receiver); if(mounted)ScaffoldMessenger.of(c).showSnackBar(SnackBar(content:Text('تم إرسال ${g['name']} ✨'))); } catch(e){ if(mounted)ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content:Text('الرصيد غير كافٍ أو تعذر إرسال الهدية'))); } },child:Container(decoration:BoxDecoration(borderRadius:BorderRadius.circular(18),gradient:const LinearGradient(colors:[Color(0xFF35134F),Color(0xFF15182F)]),border:Border.all(color:purple.withOpacity(.5))),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text(g['emoji']??'🎁',style:const TextStyle(fontSize:34)),Text(g['name']??'هدية',overflow:TextOverflow.ellipsis),Text('${g['coins']} 🪙',style:const TextStyle(color:gold,fontSize:11))])));}),),
      ])))));
    } catch(e){ if(mounted)ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content:Text('تعذر تحميل الهدايا'))); }
  }

  @override void dispose(){ if(seated){ Api.seatLeave(widget.roomId); } for(final p in peers.values)p.close();localStream?.dispose();localRenderer.dispose();remoteRenderer.dispose();channel?.sink.close();msg.dispose();super.dispose();}
  @override Widget build(BuildContext c)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(
    appBar:AppBar(title:Row(children:[const Text('LiveStar 👑'),const SizedBox(width:8),Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:3),decoration:BoxDecoration(color:gold.withOpacity(.16),borderRadius:BorderRadius.circular(12)),child:const Text('VIP ROOM',style:TextStyle(fontSize:10,color:gold,fontWeight:FontWeight.bold)))]),actions:[if(myId==hostId) IconButton(onPressed:()=>_moderateSheet(c),icon:const Icon(Icons.admin_panel_settings,color:gold)),Padding(padding:const EdgeInsets.all(14),child:Icon(Icons.circle,size:12,color:connected?Colors.green:Colors.red))]),
    body:Stack(children:[
      Container(decoration:const BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Color(0xFF32124D),bg]))),
      Column(children:[
        const SizedBox(height:10),
        Padding(padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),child:Column(children:[
          Row(children:[const Icon(Icons.mic,color:gold),const SizedBox(width:8),const Text('مقاعد المايك • 20 مقعد • $viewers مشاهد',style:TextStyle(fontWeight:FontWeight.bold)),const Spacer(),if(myId!=hostId) IconButton(onPressed:seated?(){_send('seat_leave');setState(()=>seated=false);}:(){_send('seat_request');},icon:Icon(seated?Icons.exit_to_app:Icons.mic,color:gold))]),
          const SizedBox(height:6),
          SizedBox(height:178,child:GridView.builder(padding:const EdgeInsets.symmetric(horizontal:2),gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:4,mainAxisSpacing:7,crossAxisSpacing:7,childAspectRatio:1.05),itemCount:20,itemBuilder:(_,idx){final i=idx+1; final u=seats[i]; final mine=u?['id']==myId; final muted=u?['status']=='muted'; return InkWell(borderRadius:BorderRadius.circular(15),onTap:(){if(u==null && !seated && myId!=hostId)_send('seat_request');},child:AnimatedContainer(duration:const Duration(milliseconds:250),decoration:BoxDecoration(gradient:u==null?null:LinearGradient(colors:[const Color(0xFF3A1B57),const Color(0xFF171A36)]),color:u==null?card:null,borderRadius:BorderRadius.circular(15),border:Border.all(color:mine?gold:(u!=null?purple.withOpacity(.55):Colors.white10),width:mine?2:1),boxShadow:mine?[BoxShadow(color:gold.withOpacity(.22),blurRadius:12)]:null),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[CircleAvatar(radius:18,backgroundColor:u==null?Colors.white10:pink.withOpacity(.18),child:Icon(u==null?Icons.mic_none:(muted?Icons.mic_off:Icons.mic),color:u==null?Colors.white38:(muted?pink:gold),size:18)),const SizedBox(height:4),Text(u==null?'$i':u['name']??'مستخدم',overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:9,fontWeight:mine?FontWeight.bold:FontWeight.normal)),if(u!=null) Text(mine?'أنت':'VIP',style:const TextStyle(fontSize:8,color:gold,fontWeight:FontWeight.bold))])));}))
        ])),
        if(myId==hostId && seatRequests.isNotEmpty) Container(height:58,margin:const EdgeInsets.symmetric(horizontal:10),decoration:BoxDecoration(color:card,borderRadius:BorderRadius.circular(16)),child:ListView.builder(scrollDirection:Axis.horizontal,itemCount:seatRequests.length,itemBuilder:(_,i){final q=seatRequests[i];return Padding(padding:const EdgeInsets.symmetric(horizontal:5),child:ActionChip(label:Text('طلب ${q['user']?['name']??'ضيف'}'),onPressed:() async { try { await Api.seatResponse(widget.roomId,int.parse(q['requestId'].toString()),'accept'); } catch(e) {} },avatar:const Icon(Icons.check,color:gold),));})),
        Expanded(child:Stack(children:[
          if(activeGift!=null) Positioned.fill(child:IgnorePointer(child:Center(child:TweenAnimationBuilder<double>(tween:Tween(begin:.45,end:1),duration:const Duration(milliseconds:750),curve:Curves.elasticOut,builder:(_,v,__)=>
            Transform.scale(scale:v,child:Stack(alignment:Alignment.center,children:[
              ...List.generate(14,(i)=>Transform.rotate(angle:i*.45,child:Padding(padding:EdgeInsets.only(bottom:95+((i%3)*18)),child:Text(i.isEven?'✨':'💫',style:TextStyle(fontSize:18+((i%4)*5))))))),
              Container(padding:const EdgeInsets.symmetric(horizontal:30,vertical:22),decoration:BoxDecoration(borderRadius:BorderRadius.circular(30),gradient:const LinearGradient(colors:[Color(0xFF4B1B70),Color(0xFFD11A9C),Color(0xFF8B5A00)]),boxShadow:[BoxShadow(blurRadius:42,color:Color(0x99FF20C8)),BoxShadow(blurRadius:18,color:Color(0x66FFC83D))]),child:Column(mainAxisSize:MainAxisSize.min,children:[
                Text(activeGift!['emoji']??'🎁',style:const TextStyle(fontSize:72)),
                const SizedBox(height:5),
                Text('${activeGift!['user']?['name']??'مستخدم'} أرسل هدية',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:18)),
                const SizedBox(height:4),Text(activeGift!['gift']??'هدية فاخرة',style:const TextStyle(color:gold,fontSize:16,fontWeight:FontWeight.bold)),
                if(activeGift!['coins']!=null) Text('${activeGift!['coins']} 🪙',style:const TextStyle(color:Colors.white70,fontSize:12)),
              ]))
            ]))))),
          Positioned.fill(child:RTCVideoView(remoteRenderer,objectFit:RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,mirror:true)),
          Positioned(top:12,right:12,width:115,height:165,child:ClipRRect(borderRadius:BorderRadius.circular(16),child:RTCVideoView(localRenderer,mirror:true,objectFit:RTCVideoViewObjectFit.RTCVideoViewObjectFitCover))),
          if(remoteRenderer.srcObject==null) const Center(child:Column(mainAxisSize:MainAxisSize.min,children:[CircleAvatar(radius:48,backgroundColor:pink,child:Icon(Icons.person,size:55)),SizedBox(height:10),Text('بانتظار بث المضيف…',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold))])),
          Positioned(top:12,left:12,child:Row(children:[Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),decoration:BoxDecoration(color:Colors.black54,borderRadius:BorderRadius.circular(18)),child:Text(connected?'🔴 مباشر':'جاري الاتصال...')),const SizedBox(width:8),Container(padding:const EdgeInsets.symmetric(horizontal:9,vertical:6),decoration:BoxDecoration(color:Colors.black54,borderRadius:BorderRadius.circular(18)),child:Text('👥 $viewers'))])) ,
        ])),
        SizedBox(height:105,child:ListView.builder(reverse:true,padding:const EdgeInsets.all(12),itemCount:events.length,itemBuilder:(_,i){final e=events[events.length-1-i];if(e['type']=='chat'){final u=e['user']??{};return Padding(padding:const EdgeInsets.symmetric(vertical:3),child:Text('${u['name']??'مستخدم'}: ${e['text']??''}'));}if(e['type']=='sticker'){final u=e['user']??{};final st=e['sticker']??{};return Padding(padding:const EdgeInsets.symmetric(vertical:4),child:Row(children:[Text('${u['name']??'مستخدم'}  '),_VipMini(level:int.tryParse('${u['vipLevel']??0}')??0),const SizedBox(width:5),_AnimatedStickerBubble(visual:'${st['visual']??'✨'}',name:'${st['name']??'ملصق'}')]));}if(e['type']=='presence'){return Text(e['action']=='join'?'🟢 ${e['user']?['name']} دخل الغرفة':'⚪ ${e['user']?['name']} خرج',style:const TextStyle(color:Colors.white60));}return const SizedBox.shrink();})),
        Container(padding:const EdgeInsets.fromLTRB(8,6,8,14),child:Row(children:[
          IconButton(onPressed:_toggleMic,icon:Icon(mic?Icons.mic:Icons.mic_off,color:mic?Colors.white:pink)),
          if(widget.mode!='voice') IconButton(onPressed:_toggleCam,icon:Icon(cam?Icons.videocam:Icons.videocam_off,color:cam?Colors.white:pink)),
          Expanded(child:TextField(controller:msg,onSubmitted:(_)=>_chat(),decoration:const InputDecoration(hintText:'اكتب رسالة...'))),
          IconButton(onPressed:()=>_stickerSheet(c),icon:const Icon(Icons.auto_awesome,color:gold)),
          IconButton(onPressed:_chat,icon:const Icon(Icons.send,color:pink)),
          IconButton(onPressed:() async { try { final r=await Api.likeRoom(widget.roomId); setState(()=>likes=int.tryParse(r['likes'].toString())??likes); } catch(_) {} },icon:Icon(Icons.favorite,color:pink)),
          Text('$likes',style:const TextStyle(color:pink,fontWeight:FontWeight.bold)),
          IconButton(onPressed:()=>_roomGiftSheet(c),icon:const Icon(Icons.card_giftcard,color:gold))
        ]))
      ])
    ]));
}

class Gifts extends StatelessWidget {
  const Gifts({super.key});
  static const data = [
    ['🌹','وردة ملكية','10'],
    ['💖','قلب ماسي','100'],
    ['👑','تاج الملوك','1,000'],
    ['🦋','فراشة لامعة','5,000'],
    ['💎','ماسة نادرة','25,000'],
    ['🚘','سيارة فاخرة','75,000'],
    ['🛩️','طائرة خاصة','150,000'],
    ['🦄','وحيد القرن الأسطوري','300,000'],
    ['🏰','قصر الأحلام','750,000'],
    ['🌌','مجرة النجوم','1,500,000'],
  ];
  @override Widget build(BuildContext c) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('الهدايا والمؤثرات')),
      body: Column(children: [
        Container(
          margin: const EdgeInsets.fromLTRB(14, 14, 14, 4),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(colors: [Color(0xFF5A1DB8), Color(0xFFD11A9C), Color(0xFFB77A00)]),
          ),
          child: const Row(children: [
            Icon(Icons.auto_awesome, color: Colors.white, size: 30),
            SizedBox(width: 10),
            Expanded(child: Text(
              'الهدايا الأسطورية ✨\nتظهر بتأثيرات فاخرة داخل الغرفة',
              style: TextStyle(fontWeight: FontWeight.bold),
            )),
          ]),
        ),
        Expanded(child: GridView.builder(
        padding: const EdgeInsets.all(14), itemCount: data.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12),
        itemBuilder: (_, i) => InkWell(
          onTap: () => _gift(c, data[i][1], data[i][2]),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: purple.withOpacity(.55)),
              gradient: const LinearGradient(colors: [Color(0xFF2B124A), Color(0xFF10142C)]),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(data[i][0], style: const TextStyle(fontSize: 55)),
              Text(data[i][1], style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('${data[i][2]} 🪙', style: const TextStyle(color: gold)),
            ]),
          ),
        )),
      ]),
    ),
  );
  void _gift(BuildContext c, String name, String price) => showDialog(
    context: c, builder: (_) => AlertDialog(
      title: Text('إرسال $name'),
      content: Text('سيتم خصم $price كوينز وإظهار مؤثر ثلاثي الأبعاد فخم لجميع المشاهدين.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(c), child: const Text('إرسال')),
      ],
    ));
}

class Wallet extends StatefulWidget {
  const Wallet({super.key});
  @override State<Wallet> createState()=>_WalletState();
}
class _WalletState extends State<Wallet>{
  List<dynamic> packages=[]; bool loading=true;
  @override void initState(){super.initState(); _load();}
  Future<void> _load() async { try { final r=await http.get(Uri.parse('${Api.base}/wallet/packages'),headers:Api._headers()); if(r.statusCode<300) packages=jsonDecode(r.body) as List<dynamic>; } catch(_){} if(mounted)setState(()=>loading=false); }
  @override Widget build(BuildContext c) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('المحفظة')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(colors: [Color(0xFF42127F), Color(0xFF8D176F)])),
          child: const Column(children: [
            Text('رصيد الكوينز', style: TextStyle(color: Colors.white70)),
            SizedBox(height: 6), Text('12,450 🪙', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
          ]),
        ),
        const SizedBox(height: 20),
        const Text('طرق الشحن', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        ...[
          ['💳','Visa / Mastercard'],['G','Google Pay'],['','Apple Pay'],['📱','رصيد آسياسيل عبر ID']
        ].map((x) => Card(color: card, child: ListTile(
          leading: Text(x[0], style: const TextStyle(fontSize: 25)),
          title: Text(x[1]),
          trailing: const Icon(Icons.chevron_left),
          onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const Recharge())),
        ))),
        const SizedBox(height: 18),
        const Text('باقات الكوينز', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('يبدأ الشحن من 4 دولار مقابل 30,000 كوينز، والحد الأعلى 600 دولار.',
          style: TextStyle(color: Colors.white60)),
        const SizedBox(height: 10),
        if(loading) const Center(child:CircularProgressIndicator()),
        ...packages.map((p){ final coins=p['coins']; final price=p['priceUsd']; final diamonds=p['diamondBonus'] ?? 0; final id=int.parse('${p['id']}'); return Card(color:card,child:ListTile(leading:const Icon(Icons.monetization_on,color:gold),title:Text('$coins كوينز'),subtitle:Text('\$price  •  +$diamonds 💎 مجاني',style:const TextStyle(color:gold,fontWeight:FontWeight.bold)),trailing:FilledButton(onPressed:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>Recharge(packageId:id,coins:coins,price:price))),child:const Text('شراء'))); }),
      ]),
    ),
  );
}

class Recharge extends StatelessWidget {
  final int packageId; final dynamic coins; final dynamic price;
  const Recharge({super.key,this.packageId=1,this.coins='30,000',this.price=4});
  @override Widget build(BuildContext c) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('إتمام الشحن')),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('$coins 🪙', textAlign: TextAlign.center, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: gold)),
          const SizedBox(height: 30),
          Text('$coins كوينز مقابل \$${price}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _method(c, '💳', 'Visa / Mastercard'),
          _method(c, 'G', 'Google Pay'),
          _method(c, '', 'Apple Pay'),
          _method(c, '📱', 'رصيد آسياسيل عبر ID'),
          const Spacer(),
          GButton('إنشاء طلب دفع', () async {
            final method=await showModalBottomSheet<String>(context:c,backgroundColor:card,builder:(_)=>Column(mainAxisSize:MainAxisSize.min,children:[for(final m in const ['card','google_pay','apple_pay','asiacell']) ListTile(title:Text(m=='card'?'Visa / Mastercard':m=='google_pay'?'Google Pay':m=='apple_pay'?'Apple Pay':'رصيد آسياسيل'),onTap:()=>Navigator.pop(c,m))]));
            if(method==null)return; try{ final r=await http.post(Uri.parse('${Api.base}/payments/orders'),headers:Api._headers(),body:jsonEncode({'packageId':packageId,'method':method})); if(!mounted)return; showDialog(context:c,builder:(_)=>AlertDialog(title:const Text('تم إنشاء الطلب'),content:Text(r.statusCode<300?'رقم الطلب: ${jsonDecode(r.body)['orderId']}\nالحالة: بانتظار تأكيد بوابة الدفع':'تعذر إنشاء الطلب'))); }catch(_){if(mounted)ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content:Text('تعذر الاتصال بالسيرفر')));}},
        ]),
      ),
    ),
  );
  Widget _method(BuildContext c, String icon, String title) => Card(
    color: card,
    child: RadioListTile(
      value: title, groupValue: null, onChanged: (_) {},
      title: Row(children: [Text(icon, style: const TextStyle(fontSize: 22)), const SizedBox(width: 12), Text(title)]),
    ),
  );
}

class Profile extends StatelessWidget {
  const Profile({super.key});
  @override Widget build(BuildContext c) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('الملف الشخصي')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const CircleAvatar(radius: 55, backgroundColor: pink, child: Icon(Icons.person, size: 62)),
        const SizedBox(height: 12),
        const Text('مهند 👑', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const Text('ID: 365478', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)),
        const SizedBox(height: 25),
        _row(c, Icons.edit, 'تعديل الملف'),
        _row(c, Icons.card_giftcard, 'الهدايا والإجمالي'),
        _row(c, Icons.receipt_long, 'سجل المعاملات'),
        _row(c, Icons.notifications, 'الإشعارات'),
        _row(c, Icons.security, 'الأمان والخصوصية'),
        _row(c, Icons.workspace_premium, 'VIP والمستويات', const VipPage()),
        _row(c, Icons.leaderboard, 'المتصدرين 🏆', const LeaderboardPage()),
        _row(c, Icons.people_alt_outlined, 'المتابعون والمتابَعون', const SocialPage()),
        _row(c, Icons.account_balance_wallet, 'الأرباح والسحب', const EarningsPage()),
        _row(c, Icons.swap_horiz, 'تحويل الكوينز', const TransferPage()),
        _row(c, Icons.receipt_long, 'سجل العمليات', const TransactionsPage()),
        _row(c, Icons.settings, 'الإعدادات', const SettingsPage()),
      ]),
    ),
  );
  Widget _row(BuildContext c, IconData i, String t, Widget page) => Card(
    color: card,
    child: ListTile(
      leading: Icon(i, color: pink),
      title: Text(t),
      trailing: const Icon(Icons.chevron_left),
      onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => page)),
    ));
}

class Notifications extends StatelessWidget {
  const Notifications({super.key});
  @override Widget build(BuildContext c) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('الإشعارات')),
      body: ListView(
        children: ['Sara أرسلت لك هدية 🌹','Ahmed بدأ بثاً مباشراً','لديك متابع جديد','تم شحن 2,500 كوينز بنجاح']
          .map((t) => ListTile(
            leading: const CircleAvatar(backgroundColor: purple, child: Icon(Icons.notifications)),
            title: Text(t), subtitle: const Text('منذ دقائق')))
          .toList(),
      ),
    ),
  );
}


class EarningsPage extends StatelessWidget {
  const EarningsPage({super.key});
  @override
  Widget build(BuildContext c) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('الأرباح والسحب')),
      body: ListView(padding: const EdgeInsets.all(16), children: const [
        Card(
          color: card,
          child: ListTile(
            title: Text('أرباح هذا الشهر'),
            subtitle: Text('0.00 USD'),
            leading: Icon(Icons.trending_up, color: Colors.green),
          ),
        ),
        Card(
          color: card,
          child: ListTile(
            title: Text('الرصيد القابل للسحب'),
            subtitle: Text('0.00 USD'),
            leading: Icon(Icons.account_balance_wallet, color: gold),
          ),
        ),
        SizedBox(height: 12),
        Text('السحب الحقيقي يحتاج نظام KYC، حد أدنى للسحب، وبوابة دفع/تحويل رسمية.'),
      ]),
    ),
  );
}


class VipPage extends StatefulWidget { const VipPage({super.key}); @override State<VipPage> createState()=>_VipPageState(); }
class _VipPageState extends State<VipPage>{ Map<String,dynamic>? status; bool loading=true;
  @override void initState(){super.initState();_load();}
  Future<void> _load() async { try{status=await Api.vipStatus();}catch(_){} if(mounted)setState(()=>loading=false);}
  @override Widget build(BuildContext c){ final level=int.tryParse('${status?['level']??Api.me?['vipLevel']??0}')??0; final days=int.tryParse('${status?['daysRemaining']??0}')??0; return Directionality(textDirection:TextDirection.rtl,child:Scaffold(appBar:AppBar(title:const Text('VIP 1 - 30 👑')),body:loading?const Center(child:CircularProgressIndicator()):RefreshIndicator(onRefresh:_load,child:ListView(padding:const EdgeInsets.all(16),children:[Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(borderRadius:BorderRadius.circular(26),gradient:const LinearGradient(colors:[Color(0xFF5C20A8),Color(0xFFE01CA9),Color(0xFFB77A00)])),child:Column(children:[const Icon(Icons.workspace_premium,size:58,color:gold),Text('VIP $level',style:const TextStyle(fontSize:30,fontWeight:FontWeight.w900)),Text(level==0?'ابدأ من VIP 1':days>0?'متبقي $days يوم':'انتهت المدة — ينخفض المستوى تدريجياً كل 30 يوم'),const SizedBox(height:12),if(level>=7)const Text('✨ صورة متحركة • إطار • دخول • فقاعة اسم',style:TextStyle(color:gold,fontWeight:FontWeight.bold)),const SizedBox(height:12),GButton('تجديد 30 يوم',() async { try{await Api.renewVip(level==0?1:level); await _load(); if(mounted)ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content:Text('تم تجديد VIP لمدة 30 يوم')));}catch(e){}})])),const SizedBox(height:16),const Text('طبقات VIP',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:8),...List.generate(30,(i){final n=i+1;final active=n<=level;final special=n>=7;return Card(color:card,child:ListTile(leading:CircleAvatar(backgroundColor:active?gold:Colors.white10,child:Text('$n',style:TextStyle(color:active?Colors.black:Colors.white))),title:Row(children:[Text('VIP $n'),if(special)const Padding(padding:EdgeInsets.only(right:6),child:Icon(Icons.auto_awesome,color:pink,size:17))]),subtitle:Text(special?'صورة متحركة + إطار + تأثير دخول + فقاعة اسم + ملصقات متحركة':'شارات VIP ومزايا المستوى'),trailing:Text(n==1?'بداية':n==30?'MAX':'XP ${n*1000}',style:const TextStyle(color:gold,fontSize:11)));}),const SizedBox(height:10),const Text('نظام المدة: كل تفعيل VIP صالح 30 يوماً. عند انتهاء المدة وعدم التجديد، ينخفض VIP مستوى واحداً لكل 30 يوماً إضافية، حتى يصل إلى VIP 0. VIP 7+ يفتح المزايا المتحركة.',style:TextStyle(color:Colors.white60,height:1.5))]))); }
}

class _VipMini extends StatelessWidget { final int level; const _VipMini({required this.level}); @override Widget build(BuildContext c)=>level>0?Container(padding:const EdgeInsets.symmetric(horizontal:5,vertical:2),decoration:BoxDecoration(color:gold.withOpacity(.14),borderRadius:BorderRadius.circular(8)),child:Text('VIP $level',style:const TextStyle(fontSize:8,color:gold,fontWeight:FontWeight.bold))):const SizedBox.shrink(); }
class _AnimatedStickerBubble extends StatefulWidget { final String visual,name; const _AnimatedStickerBubble({required this.visual,required this.name}); @override State<_AnimatedStickerBubble> createState()=>_AnimatedStickerBubbleState(); }
class _AnimatedStickerBubbleState extends State<_AnimatedStickerBubble> with SingleTickerProviderStateMixin { late AnimationController ac; @override void initState(){super.initState();ac=AnimationController(vsync:this,duration:const Duration(milliseconds:900))..repeat(reverse:true);} @override void dispose(){ac.dispose();super.dispose();} @override Widget build(BuildContext c)=>AnimatedBuilder(animation:ac,builder:(_,__) {final s=1+(ac.value*.12);return Transform.scale(scale:s,child:Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFF341454),Color(0xFF9B1FAE)]),borderRadius:BorderRadius.circular(16),boxShadow:[BoxShadow(color:pink.withOpacity(.18),blurRadius:10)]),child:Row(mainAxisSize:MainAxisSize.min,children:[Text(widget.visual,style:const TextStyle(fontSize:25)),const SizedBox(width:5),Text(widget.name,style:const TextStyle(fontSize:10,fontWeight:FontWeight.bold))])));}); }

class TransferPage extends StatefulWidget { const TransferPage({super.key}); @override State<TransferPage> createState()=>_TransferPageState(); }
class _TransferPageState extends State<TransferPage>{ final id=TextEditingController(); final amount=TextEditingController(); bool loading=false;
 Future<void> doTransfer() async { final n=int.tryParse(amount.text.trim()); if(n==null||n<10){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('الحد الأدنى للتحويل 10 كوينز')));return;} setState(()=>loading=true); try { await Api.transfer(id.text.trim(),n); await Api.profile(); if(mounted){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تم التحويل بنجاح'))); Navigator.pop(context,true);} } catch(e){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('فشل التحويل: $e')));} finally{if(mounted)setState(()=>loading=false);} }
 @override Widget build(BuildContext c)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(appBar:AppBar(title:const Text('تحويل الكوينز')),body:Padding(padding:const EdgeInsets.all(18),child:Column(children:[TextField(controller:id,decoration:const InputDecoration(labelText:'ID المستلم',filled:true)),const SizedBox(height:12),TextField(controller:amount,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'عدد الكوينز',filled:true)),const SizedBox(height:18),GButton(loading?'جاري التحويل...':'تحويل الآن',loading?() : doTransfer),const SizedBox(height:16),const Text('يتم التحقق من الرصيد والـID على الخادم قبل التنفيذ.',style:TextStyle(color:Colors.white54))])));
}

class TransactionsPage extends StatefulWidget { const TransactionsPage({super.key}); @override State<TransactionsPage> createState()=>_TransactionsPageState(); }
class _TransactionsPageState extends State<TransactionsPage>{ late Future<List<dynamic>> future; @override void initState(){super.initState(); future=Api.transactions();}
 @override Widget build(BuildContext c)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(appBar:AppBar(title:const Text('سجل العمليات')),body:FutureBuilder<List<dynamic>>(future:future,builder:(c,s){if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());if(s.hasError)return Center(child:Text('تعذر تحميل السجل'));final rows=s.data??[];if(rows.isEmpty)return const Center(child:Text('لا توجد عمليات بعد'));return RefreshIndicator(onRefresh:()async=>setState(()=>future=Api.transactions()),child:ListView.builder(itemCount:rows.length,itemBuilder:(c,i){final x=rows[i] as Map;return ListTile(leading:const Icon(Icons.receipt_long),title:Text('${x['type']} • ${x['coins']} 🪙'),subtitle:Text('${x['reference']??''}'),trailing:Text('${x['amount_usd']??''}');}));})));
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext c) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        children: [
          SwitchListTile(value: true, onChanged: (_) {}, title: const Text('إشعارات الهدايا')),
          SwitchListTile(value: true, onChanged: (_) {}, title: const Text('إشعارات الرسائل')),
          const ListTile(leading: Icon(Icons.language), title: Text('اللغة'), trailing: Text('العربية')),
          const ListTile(leading: Icon(Icons.lock), title: Text('الخصوصية')),
          const ListTile(leading: Icon(Icons.support_agent), title: Text('الدعم والمساعدة')),
          const ListTile(leading: Icon(Icons.description), title: Text('الشروط والسياسات')),
        ],
      ),
    ),
  );
}


class LeaderboardPage extends StatefulWidget { const LeaderboardPage({super.key}); @override State<LeaderboardPage> createState()=>_LeaderboardPageState(); }
class _LeaderboardPageState extends State<LeaderboardPage>{ List<dynamic> rows=[]; bool loading=true; @override void initState(){super.initState(); _load();} Future<void> _load() async { try { rows=await Api.leaderboard(); } finally { if(mounted)setState(()=>loading=false); } } @override Widget build(BuildContext c)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(appBar:AppBar(title:const Text('المتصدرين 🏆')),body:loading?const Center(child:CircularProgressIndicator()):RefreshIndicator(onRefresh:_load,child:ListView.builder(itemCount:rows.length,itemBuilder:(_,i){final u=Map<String,dynamic>.from(rows[i]);final rank=i+1;return Card(color:card,margin:const EdgeInsets.symmetric(horizontal:12,vertical:5),child:ListTile(leading:CircleAvatar(backgroundColor:rank<=3?gold:purple,child:Text('$rank')),title:Text('${u['name']??'مستخدم'}  ${rank<=3?'👑':''}'),subtitle:Text('ID: ${u['id']} • ${u['followers']} متابع'),trailing:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text('${u['xp']} XP',style:const TextStyle(color:gold,fontWeight:FontWeight.bold)),Text('VIP ${u['vipLevel']}',style:const TextStyle(color:pink,fontSize:11))])));}))); }

class SocialPage extends StatefulWidget { const SocialPage({super.key}); @override State<SocialPage> createState()=>_SocialPageState(); }
class _SocialPageState extends State<SocialPage>{ Map<String,dynamic>? me; bool loading=true; final id=TextEditingController(); @override void initState(){super.initState(); _load();} Future<void> _load() async { try { if(Api.me?['id']!=null) me=await Api.social(Api.me!['id'].toString()); } finally { if(mounted)setState(()=>loading=false); } } Future<void> _toggle() async { if(me==null)return; final r=me!['isFollowing']==true?await Api.unfollow(me!['id'].toString()):await Api.follow(me!['id'].toString()); setState(()=>me={...me!,...r,'isFollowing':r['following']}); } @override Widget build(BuildContext c)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(appBar:AppBar(title:const Text('المتابعون')),body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(16),children:[if(me!=null)Card(color:card,child:ListTile(leading:const CircleAvatar(radius:28,backgroundColor:pink,child:Icon(Icons.person)),title:Text(me!['name']??'مستخدم'),subtitle:Text('ID: ${me!['id']}\n${me!['followers']} متابع • ${me!['following']} يتابع'),trailing:FilledButton(onPressed:_toggle,child:Text(me!['isFollowing']==true?'إلغاء المتابعة':'متابعة')))),const SizedBox(height:18),const Text('ابحث عن مستخدم للمتابعة',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const SizedBox(height:8),TextField(controller:id,decoration:const InputDecoration(hintText:'أدخل ID مثل LS12345678')),const SizedBox(height:8),FilledButton(onPressed:() async { try { final x=await Api.social(id.text.trim()); if(mounted)showDialog(context:c,builder:(_)=>AlertDialog(title:Text(x['name']??'مستخدم'),content:Text('ID: ${x['id']}\n${x['followers']} متابع\n${x['following']} يتابع'),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('إغلاق'))])); } catch(_) { ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content:Text('المستخدم غير موجود'))); } },child:const Text('عرض'))]))); }
