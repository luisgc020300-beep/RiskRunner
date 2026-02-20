import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'resumen_screen.dart';

class SocialScreen extends StatefulWidget {
  const SocialScreen({super.key});

  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen> {
  final String currentUserId = FirebaseAuth.instance.currentUser!.uid;
  final TextEditingController _searchController = TextEditingController();
  
  Map<String, dynamic>? _userEncontrado;
  String? _userEncontradoId;
  bool _yaSonAmigos = false;
  bool _solicitudPendiente = false;

  void _buscarUsuario() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    final result = await FirebaseFirestore.instance
        .collection('players')
        .where('nickname', isEqualTo: query)
        .get();

    if (result.docs.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Usuario no encontrado")));
      setState(() {
        _userEncontrado = null;
        _userEncontradoId = null;
      });
      return;
    }

    final userData = result.docs.first;
    final targetId = userData.id;

    if (targetId == currentUserId) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("¡Eres tú!")));
      return;
    }

    final friendshipCheck = await FirebaseFirestore.instance
        .collection('friendships')
        .where('senderId', whereIn: [currentUserId, targetId])
        .get();

    String relacionActual = "ninguna";
    
    for (var doc in friendshipCheck.docs) {
      final data = doc.data();
      if ((data['senderId'] == currentUserId && data['receiverId'] == targetId) ||
          (data['senderId'] == targetId && data['receiverId'] == currentUserId)) {
        relacionActual = data['status']; 
        break;
      }
    }

    setState(() {
      _userEncontrado = userData.data();
      _userEncontradoId = targetId;
      _yaSonAmigos = (relacionActual == 'accepted');
      _solicitudPendiente = (relacionActual == 'pending');
    });
  }

  Future<void> _enviarSolicitud() async {
    if (_userEncontradoId == null || _solicitudPendiente || _yaSonAmigos) return;
    
    await FirebaseFirestore.instance.collection('friendships').add({
      'senderId': currentUserId,
      'receiverId': _userEncontradoId,
      'status': 'pending',
      'timestamp': FieldValue.serverTimestamp(),
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Solicitud enviada")));
      setState(() {
        _userEncontrado = null;
        _solicitudPendiente = false;
      });
      _searchController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          automaticallyImplyLeading: false, // Quitamos la flecha de atrás automática
          title: const Text("Comunidad", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
          bottom: TabBar(
            indicatorColor: Colors.orange,
            labelColor: Colors.orange,
            unselectedLabelColor: Colors.white54,
            tabs: [
              const Tab(text: "Amigos"),
              Tab(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('friendships')
                      .where('receiverId', isEqualTo: currentUserId)
                      .where('status', isEqualTo: 'pending')
                      .snapshots(),
                  builder: (context, snapshot) {
                    int count = snapshot.hasData ? snapshot.data!.docs.length : 0;
                    return Badge(
                      isLabelVisible: count > 0,
                      label: Text(count.toString()),
                      backgroundColor: Colors.red,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text("Solicitudes"),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            _buildSearchBox(),
            if (_userEncontrado != null) _buildUserPreview(),
            const Divider(color: Colors.white10, thickness: 1),
            Expanded(
              child: TabBarView(
                children: [
                  _buildFriendsList(),
                  _buildRequestsList(),
                ],
              ),
            ),
          ],
        ),
        // --- BARRA DE NAVEGACIÓN UNIFICADA ---
        bottomNavigationBar: BottomNavigationBar(
          backgroundColor: const Color(0xFF1A1A1A),
          selectedItemColor: Colors.orange,
          unselectedItemColor: Colors.white54,
          currentIndex: 3, // Social es la posición 3
          type: BottomNavigationBarType.fixed,
          onTap: (index) {
            if (index == 3) return; // Ya estamos aquí
            if (index == 0) Navigator.pushReplacementNamed(context, '/home');
            if (index == 1) Navigator.pushReplacementNamed(context, '/correr');
            if (index == 2) Navigator.pushReplacementNamed(context, '/resumen');
          },
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.map_rounded), label: 'Correr'),
            BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Resumen'),
            BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Social'),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBox() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: "Nickname exacto...",
          hintStyle: const TextStyle(color: Colors.white54),
          prefixIcon: const Icon(Icons.search, color: Colors.orange),
          filled: true,
          fillColor: Colors.white10,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
          suffixIcon: IconButton(
            icon: const Icon(Icons.send, color: Colors.orange),
            onPressed: _buscarUsuario,
          ),
        ),
      ),
    );
  }

  Widget _buildUserPreview() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _yaSonAmigos ? Colors.green.withOpacity(0.5) : Colors.orange.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 25,
            backgroundColor: Colors.orange,
            child: Icon(Icons.person, color: Colors.black),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_userEncontrado!['nickname'] ?? "Usuario", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                Text("Nivel ${_userEncontrado!['nivel'] ?? 1} • ${_userEncontrado!['monedas'] ?? 0} Monedas", 
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          if (_yaSonAmigos)
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () {
                Navigator.push(
                  context, 
                  MaterialPageRoute(
                    builder: (context) => ResumenScreen(
                      targetUserId: _userEncontradoId,
                      targetNickname: _userEncontrado!['nickname'],
                      distancia: 0.0,
                      tiempo: Duration.zero,
                      ruta: const [],
                    ),
                  ),
                );
              },
              child: const Text("Ver Stats", style: TextStyle(color: Colors.white)),
            )
          else if (_solicitudPendiente)
            const Text("Pendiente", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))
          else
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: _enviarSolicitud,
              child: const Text("Agregar", style: TextStyle(color: Colors.black)),
            ),
        ],
      ),
    );
  }

  Widget _buildFriendsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('friendships')
          .where('status', isEqualTo: 'accepted')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.orange));
        
        final misAmigosDocs = snapshot.data!.docs.where((doc) => 
          doc['senderId'] == currentUserId || doc['receiverId'] == currentUserId
        ).toList();

        if (misAmigosDocs.isEmpty) return const Center(child: Text("Aún no tienes amigos", style: TextStyle(color: Colors.white54)));

        return ListView.builder(
          itemCount: misAmigosDocs.length,
          itemBuilder: (context, index) {
            final dataFriendship = misAmigosDocs[index].data() as Map<String, dynamic>;
            final friendId = dataFriendship['senderId'] == currentUserId 
                ? dataFriendship['receiverId'] 
                : dataFriendship['senderId'];

            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance.collection('players').doc(friendId).get(),
              builder: (context, userSnap) {
                if (!userSnap.hasData) return const SizedBox();
                final data = userSnap.data!.data() as Map<String, dynamic>?;
                if (data == null) return const SizedBox();
                
                return ListTile(
                  leading: const CircleAvatar(backgroundColor: Colors.white10, child: Icon(Icons.person, color: Colors.orange)),
                  title: Text(data['nickname'] ?? "Desconocido", style: const TextStyle(color: Colors.white)),
                  subtitle: Text("Nivel ${data['nivel'] ?? 1}", style: const TextStyle(color: Colors.orange, fontSize: 12)),
                  trailing: const Icon(Icons.bar_chart, color: Colors.white24),
                  onTap: () {
                    Navigator.push(
                      context, 
                      MaterialPageRoute(
                        builder: (context) => ResumenScreen(
                          targetUserId: friendId,
                          targetNickname: data['nickname'],
                          distancia: 0.0,
                          tiempo: Duration.zero,
                          ruta: const [],
                        ),
                      ),
                    );
                  },
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
      stream: FirebaseFirestore.instance.collection('friendships')
          .where('receiverId', isEqualTo: currentUserId)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.orange));
        if (snapshot.data!.docs.isEmpty) return const Center(child: Text("No hay solicitudes", style: TextStyle(color: Colors.white54)));
        
        return ListView.builder(
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            final senderId = doc['senderId'];

            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance.collection('players').doc(senderId).get(),
              builder: (context, userSnap) {
                if (!userSnap.hasData) return const SizedBox();
                final userData = userSnap.data!.data() as Map<String, dynamic>?;
                final name = userData?['nickname'] ?? "Usuario";

                return ListTile(
                  leading: const Icon(Icons.person_add, color: Colors.orange),
                  title: Text(name, style: const TextStyle(color: Colors.white)),
                  subtitle: const Text("Quiere ser tu amigo", style: TextStyle(color: Colors.white54, fontSize: 12)),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    onPressed: () => FirebaseFirestore.instance.collection('friendships').doc(doc.id).update({'status': 'accepted'}),
                    child: const Text("Aceptar", style: TextStyle(color: Colors.white)),
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