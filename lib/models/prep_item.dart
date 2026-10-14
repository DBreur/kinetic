// prep_item.dart — een voorbereidingsactie voor een training, bv. "30 g
// koolhydraten" om "18:30". Volledig door de gebruiker zelf ingevoerd, geen
// vaste lijst.

class PrepItem {
  final String time; // "HH:mm"
  final String label;
  final bool done;

  const PrepItem({required this.time, required this.label, this.done = false});

  factory PrepItem.fromJson(Map<String, dynamic> json) => PrepItem(
    time: json['time'] as String? ?? '',
    label: json['label'] as String? ?? '',
    done: json['done'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {'time': time, 'label': label, 'done': done};

  PrepItem copyWith({String? time, String? label, bool? done}) => PrepItem(
    time: time ?? this.time,
    label: label ?? this.label,
    done: done ?? this.done,
  );
}
