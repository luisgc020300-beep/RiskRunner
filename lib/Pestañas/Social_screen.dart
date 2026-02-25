import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'Resumen_screen.dart';
import '../Widgets/custom_navbar.dart';

class SocialScreen extends StatefulWidget {
  const SocialScreen({super.key});

  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen>
    with SingleTickerProviderStateMixin {
  final String currentUserId = FirebaseAuth.instance.currentUser!.uid;
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;

  Map<String, dynamic>? _userEncontrado;
  String? _userEncontradoId;
  bool _yaSonAmigos = false;
  bool _solicitudPendiente = false;
  int? _rangoEncontrado;
  String? _mensajeError;

  // Conteo de solicitudes pendientes para el badge
  int _solicitudesPendientes = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _searchController.clear();
          _userEncontrado = null;
          _userEncontradoId = null;
          _mensajeError = null;
          _rangoEncontrado = null;
        });
      }
    });
    _escucharSolicitudes();
  }

  void _escucharSolicitudes() {
    FirebaseFirestore.instance
        .collection('friendships')
        .where('receiverId', isEqualTo: currentUserId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snap) {
      if (mounted) {
        setState(() => _solicitudesPendientes = snap.docs.length);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _buscarUsuario() async {
    final query = _searchController.text.trim();
    setState(() {
      _userEncontrado = null;
      _mensajeError = null;
    });
    if (query.isEmpty) return;

    final result = await FirebaseFirestore.instance
        .collection('players')
        .where('nickname', isEqualTo: query)
        .get();

    if (result.docs.isEmpty) {
      setState(() => _mensajeError = "Usuario no encontrado");
      return;
    }

    final userData = result.docs.first;
    final targetId = userData.id;

    final friendshipCheck = await FirebaseFirestore.instance
        .collection('friendships')
        .where('senderId', whereIn: [currentUserId, targetId]).get();

    String relacion = "ninguna";
    bool meHaMandadoSolicitud = false;

    for (var doc in friendshipCheck.docs) {
      final data = doc.data();
      if ((data['senderId'] == currentUserId &&
              data['receiverId'] == targetId) ||
          (data['senderId'] == targetId &&
              data['receiverId'] == currentUserId)) {
        relacion = data['status'];
        if (data['receiverId'] == currentUserId &&
            data['status'] == 'pending') {
          meHaMandadoSolicitud = true;
        }
        break;
      }
    }

    if (_tabController.index == 1 && relacion != 'accepted') {
      setState(() => _mensajeError = "Usuario no encontrado");
      return;
    }
    if (_tabController.index == 2 && !meHaMandadoSolicitud) {
      setState(() => _mensajeError = "Usuario no encontrado");
      return;
    }

    final targetMonedas = userData.data()['monedas'] ?? 0;
    final rankQuery = await FirebaseFirestore.instance
        .collection('players')
        .where('monedas', isGreaterThan: targetMonedas)
        .count()
        .get();

    setState(() {
      _userEncontrado = userData.data();
      _userEncontradoId = targetId;
      _rangoEncontrado = (rankQuery.count ?? 0) + 1;
      _yaSonAmigos = (relacion == 'accepted');
      _solicitudPendiente = (relacion == 'pending');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text("Social",
            style: TextStyle(
                color: Colors.orange, fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.orange,
          tabs: [
            const Tab(text: "Ranking"),
            const Tab(text: "Amigos"),
            // Tab "Solicitudes" con badge rojo
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Solicitudes"),
                  if (_solicitudesPendientes > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _solicitudesPendientes > 9
                            ? '9+'
                            : _solicitudesPendientes.toString(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildSearchBox(),
          if (_mensajeError != null) _buildErrorBox(),
          if (_userEncontrado != null) _buildUserPreview(),
          const Divider(color: Colors.white10, thickness: 1),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildGlobalRanking(),
                _buildFriendsList(),
                _buildRequestsList(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: const CustomBottomNavbar(currentIndex: 3),
    );
  }

  Widget _buildSearchBox() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: "Buscar...",
          hintStyle: const TextStyle(color: Colors.white54),
          prefixIcon: const Icon(Icons.search, color: Colors.orange),
          filled: true,
          fillColor: Colors.white10,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none),
          suffixIcon: IconButton(
            icon: const Icon(Icons.send, color: Colors.orange),
            onPressed: _buscarUsuario,
          ),
        ),
      ),
    );
  }

  Widget _buildUserPreview() {
    int nivel = _userEncontrado!['nivel'] ?? 1;
    Color borderColor = nivel >= 10
        ? Colors.grey[400]!
        : Colors.orange.withValues(alpha: 0.5);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Row(
        children: [
          SizedBox(
              width: 50,
              child: Text("#${_rangoEncontrado ?? '?'}",
                  style: TextStyle(
                      color: borderColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 18))),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_userEncontrado!['nickname'] ?? "Usuario",
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18)),
                Text(
                    "Nivel $nivel • ${_userEncontrado!['monedas'] ?? 0} Monedas",
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          _buildActionButton(),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    if (_yaSonAmigos) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.green)),
        child: const Text("Amigo",
            style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
                fontSize: 12)),
      );
    }
    if (_solicitudPendiente) {
      return const Text("Pendiente",
          style: TextStyle(color: Colors.orange, fontSize: 12));
    }
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange,
          minimumSize: const Size(80, 35),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10))),
      onPressed: _enviarSolicitud,
      child: const Text("Agregar",
          style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 12)),
    );
  }

  Widget _buildUserTile({
    required String name,
    required int nivel,
    String? fotoBase64,
    String? rank,
    Widget? trailing,
    bool esYo = false,
    bool mostrarFoto = false,
  }) {
    Color borderColor = nivel >= 10
        ? Colors.grey[400]!
        : Colors.orange.withValues(alpha: 0.5);
    if (esYo) borderColor = Colors.orange;

    Widget avatarChild;
    if (mostrarFoto && fotoBase64 != null) {
      avatarChild = ClipOval(
        child: Image.memory(base64Decode(fotoBase64),
            fit: BoxFit.cover, width: 40, height: 40),
      );
    } else if (rank != null) {
      avatarChild = Text(rank,
          style: TextStyle(
              color: borderColor,
              fontWeight: FontWeight.bold,
              fontSize: 14));
    } else {
      avatarChild = Icon(Icons.person, color: borderColor);
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: borderColor.withValues(alpha: 0.2),
          child: avatarChild,
        ),
        title: Text(name + (esYo ? " (Tú)" : ""),
            style: TextStyle(
                color: esYo ? Colors.orange : Colors.white,
                fontWeight: FontWeight.bold)),
        subtitle: Text("Nivel $nivel",
            style: TextStyle(
                color: borderColor.withValues(alpha: 0.8), fontSize: 12)),
        trailing: trailing,
      ),
    );
  }

  Widget _buildErrorBox() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 22, 22, 22).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: const Color.fromARGB(255, 56, 56, 55)
                .withValues(alpha: 0.3)),
      ),
      child: Center(
        child: Text(_mensajeError!,
            style: const TextStyle(
                color: Colors.white54,
                fontSize: 14,
                fontStyle: FontStyle.italic)),
      ),
    );
  }

  Future<void> _enviarSolicitud() async {
    if (_userEncontradoId == null ||
        _solicitudPendiente ||
        _yaSonAmigos) return;
    await FirebaseFirestore.instance.collection('friendships').add({
      'senderId': currentUserId,
      'receiverId': _userEncontradoId,
      'status': 'pending',
      'timestamp': FieldValue.serverTimestamp(),
    });
    setState(() => _userEncontrado = null);
    _searchController.clear();
  }

  Widget _buildGlobalRanking() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('players')
          .orderBy('monedas', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(
              child: CircularProgressIndicator(color: Colors.orange));
        final docs = snapshot.data!.docs;
        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final user = docs[index].data() as Map<String, dynamic>;
            final bool esYo = docs[index].id == currentUserId;
            return _buildUserTile(
              name: user['nickname'],
              nivel: user['nivel'] ?? 1,
              rank: "#${index + 1}",
              esYo: esYo,
              mostrarFoto: false,
              trailing: Text("${user['monedas']} 🪙",
                  style: const TextStyle(
                      color: Colors.orange, fontWeight: FontWeight.bold)),
            );
          },
        );
      },
    );
  }

  Widget _buildFriendsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('friendships')
          .where('status', isEqualTo: 'accepted')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(
              child: CircularProgressIndicator(color: Colors.orange));
        final misAmigos = snapshot.data!.docs
            .where((doc) =>
                doc['senderId'] == currentUserId ||
                doc['receiverId'] == currentUserId)
            .toList();
        if (misAmigos.isEmpty)
          return const Center(
              child: Text("Aún no tienes amigos",
                  style: TextStyle(color: Colors.white54)));
        return ListView.builder(
          itemCount: misAmigos.length,
          itemBuilder: (context, index) {
            final friendId = misAmigos[index]['senderId'] == currentUserId
                ? misAmigos[index]['receiverId']
                : misAmigos[index]['senderId'];
            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('players')
                  .doc(friendId)
                  .get(),
              builder: (context, s) {
                if (!s.hasData) return const SizedBox();
                final data = s.data!.data() as Map<String, dynamic>;
                return _buildUserTile(
                  name: data['nickname'],
                  nivel: data['nivel'] ?? 1,
                  fotoBase64: data['foto_base64'] as String?,
                  mostrarFoto: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.bar_chart, color: Colors.white54),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ResumenScreen(
                          targetUserId: friendId,
                          targetNickname: data['nickname'],
                          distancia: 0,
                          tiempo: Duration.zero,
                          ruta: const [],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildRequestsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('friendships')
          .where('receiverId', isEqualTo: currentUserId)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(
              child: CircularProgressIndicator(color: Colors.orange));
        final solicitudes = snapshot.data!.docs;
        if (solicitudes.isEmpty)
          return const Center(
              child: Text("No tienes solicitudes aún",
                  style: TextStyle(color: Colors.white54)));
        return ListView.builder(
          itemCount: solicitudes.length,
          itemBuilder: (context, index) {
            final doc = solicitudes[index];
            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('players')
                  .doc(doc['senderId'])
                  .get(),
              builder: (context, s) {
                if (!s.hasData) return const SizedBox();
                final data = s.data!.data() as Map<String, dynamic>;
                return _buildUserTile(
                  name: data['nickname'],
                  nivel: data['nivel'] ?? 1,
                  fotoBase64: data['foto_base64'] as String?,
                  mostrarFoto: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close,
                            color: Colors.redAccent),
                        onPressed: () async {
                          await FirebaseFirestore.instance
                              .collection('friendships')
                              .doc(doc.id)
                              .delete();
                        },
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        onPressed: () => FirebaseFirestore.instance
                            .collection('friendships')
                            .doc(doc.id)
                            .update({'status': 'accepted'}),
                        child: const Text("Aceptar",
                            style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}