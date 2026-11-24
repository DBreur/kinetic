// technique_system.dart — een "systeem": een flow-graaf van posities en
// technieken (bv. "Open guard passing"), zoals Systems in Flowroll.

enum SystemNodeKind {
  position,
  technique,
  finish;

  static SystemNodeKind fromName(String? n) => switch (n) {
    'technique' => SystemNodeKind.technique,
    'finish' => SystemNodeKind.finish,
    _ => SystemNodeKind.position,
  };

  String get label => switch (this) {
    SystemNodeKind.position => 'Positie',
    SystemNodeKind.technique => 'Techniek',
    SystemNodeKind.finish => 'Eindpositie / finish',
  };
}

class SystemNode {
  final String id;
  final String label;
  final SystemNodeKind kind;

  /// Optioneel: gekoppelde eigen techniek, opent die bij tikken.
  final String? techniqueId;

  const SystemNode({
    required this.id,
    required this.label,
    this.kind = SystemNodeKind.position,
    this.techniqueId,
  });

  factory SystemNode.fromJson(Map<String, dynamic> j) => SystemNode(
    id: j['id'] as String,
    label: (j['label'] as String?) ?? '',
    kind: SystemNodeKind.fromName(j['kind'] as String?),
    techniqueId: j['technique_id'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'kind': kind.name,
    if (techniqueId != null) 'technique_id': techniqueId,
  };

  SystemNode copyWith({String? label, SystemNodeKind? kind}) => SystemNode(
    id: id,
    label: label ?? this.label,
    kind: kind ?? this.kind,
    techniqueId: techniqueId,
  );
}

class SystemEdge {
  final String from;
  final String to;
  const SystemEdge({required this.from, required this.to});

  factory SystemEdge.fromJson(Map<String, dynamic> j) =>
      SystemEdge(from: j['from'] as String, to: j['to'] as String);

  Map<String, dynamic> toJson() => {'from': from, 'to': to};

  @override
  bool operator ==(Object other) =>
      other is SystemEdge && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

class TechniqueSystem {
  final String id;
  final String name;
  final String notes;
  final List<SystemNode> nodes;
  final List<SystemEdge> edges;
  final List<String> tags;
  final List<String> videoUrls;
  final bool favorite;
  final DateTime? createdAt;

  const TechniqueSystem({
    required this.id,
    required this.name,
    this.notes = '',
    this.nodes = const [],
    this.edges = const [],
    this.tags = const [],
    this.videoUrls = const [],
    this.favorite = false,
    this.createdAt,
  });

  factory TechniqueSystem.fromJson(Map<String, dynamic> j) => TechniqueSystem(
    id: j['id'] as String,
    name: j['name'] as String,
    notes: (j['notes'] as String?) ?? '',
    nodes: ((j['nodes'] as List?) ?? [])
        .map((e) => SystemNode.fromJson(e as Map<String, dynamic>))
        .toList(),
    edges: ((j['edges'] as List?) ?? [])
        .map((e) => SystemEdge.fromJson(e as Map<String, dynamic>))
        .toList(),
    tags: ((j['tags'] as List?) ?? []).map((e) => e as String).toList(),
    videoUrls: ((j['video_urls'] as List?) ?? [])
        .map((e) => e as String)
        .toList(),
    favorite: (j['favorite'] as bool?) ?? false,
    createdAt: j['created_at'] == null
        ? null
        : DateTime.parse(j['created_at'] as String).toLocal(),
  );

  Map<String, dynamic> toContentJson() => {
    'name': name,
    'notes': notes,
    'nodes': nodes.map((n) => n.toJson()).toList(),
    'edges': edges.map((e) => e.toJson()).toList(),
    'tags': tags,
    'video_urls': videoUrls,
    'favorite': favorite,
  };

  TechniqueSystem copyWith({
    String? name,
    String? notes,
    List<SystemNode>? nodes,
    List<SystemEdge>? edges,
    List<String>? tags,
    List<String>? videoUrls,
    bool? favorite,
  }) => TechniqueSystem(
    id: id,
    name: name ?? this.name,
    notes: notes ?? this.notes,
    nodes: nodes ?? this.nodes,
    edges: edges ?? this.edges,
    tags: tags ?? this.tags,
    videoUrls: videoUrls ?? this.videoUrls,
    favorite: favorite ?? this.favorite,
    createdAt: createdAt,
  );

  /// Verwijdert een node én alle pijlen van/naar die node.
  TechniqueSystem withoutNode(String nodeId) => copyWith(
    nodes: nodes.where((n) => n.id != nodeId).toList(),
    edges: edges.where((e) => e.from != nodeId && e.to != nodeId).toList(),
  );

  /// Voegt een pijl toe; negeert dubbele pijlen, lussen en onbekende nodes.
  TechniqueSystem withEdge(String from, String to) {
    final ids = nodes.map((n) => n.id).toSet();
    final edge = SystemEdge(from: from, to: to);
    if (from == to ||
        !ids.contains(from) ||
        !ids.contains(to) ||
        edges.contains(edge)) {
      return this;
    }
    return copyWith(edges: [...edges, edge]);
  }
}

/// Laag (rij) per node voor de automatische layout: wortels (geen inkomende
/// pijlen) op laag 0, daarna de langste weg vanaf een wortel. Cycli worden
/// veilig afgekapt zodat de layout altijd eindigt.
Map<String, int> systemLayers(TechniqueSystem s) {
  final incoming = <String, int>{for (final n in s.nodes) n.id: 0};
  final out = <String, List<String>>{for (final n in s.nodes) n.id: []};
  for (final e in s.edges) {
    if (!incoming.containsKey(e.from) || !incoming.containsKey(e.to)) continue;
    incoming[e.to] = incoming[e.to]! + 1;
    out[e.from]!.add(e.to);
  }
  final layer = <String, int>{};
  var roots = s.nodes.where((n) => incoming[n.id] == 0).map((n) => n.id);
  if (roots.isEmpty && s.nodes.isNotEmpty) roots = [s.nodes.first.id];
  final queue = <String>[];
  for (final r in roots) {
    layer[r] = 0;
    queue.add(r);
  }
  final maxLayer = s.nodes.length;
  while (queue.isNotEmpty) {
    final id = queue.removeAt(0);
    for (final next in out[id]!) {
      final candidate = layer[id]! + 1;
      if (candidate > maxLayer) continue; // cyclus
      if ((layer[next] ?? -1) < candidate) {
        layer[next] = candidate;
        queue.add(next);
      }
    }
  }
  // Losse nodes die alleen in een cyclus zitten zonder wortel: laag 0.
  for (final n in s.nodes) {
    layer.putIfAbsent(n.id, () => 0);
  }
  return layer;
}
