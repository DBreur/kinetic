import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic/models/library.dart';
import 'package:kinetic/models/technique.dart';

void main() {
  test('dubbel-gecodeerde bibliotheektekst wordt hersteld', () {
    expect(repairMojibake('KnieÃ«n hoog'), 'Knieën hoog');
    expect(repairMojibake('EÃ©n underhook'), 'Eén underhook');
    expect(repairMojibake('Gewone tekst'), 'Gewone tekst');
    expect(repairMojibake('Knieën blijft'), 'Knieën blijft');
  });

  test('bibliotheek-indeling volgens kinetic-design', () {
    expect(TechniqueGroup.classify('Takedown', 'Throw'), TechniqueGroup.throws);
    expect(TechniqueGroup.classify('Strike', 'Kick'), TechniqueGroup.striking);
    expect(TechniqueGroup.classify('Strike', 'Defense'), TechniqueGroup.defense);
    expect(TechniqueGroup.classify('Submission', 'Choke'), TechniqueGroup.submissions);
    expect(TechniqueGroup.classify('Overig', 'Sweep'), TechniqueGroup.sweeps);
    expect(TechniqueGroup.classify('Overig', 'Pass'), TechniqueGroup.sweeps);
    expect(TechniqueGroup.classify('Overig', 'Control'), TechniqueGroup.control);
    expect(TechniqueGroup.classify('Overig', 'Escape'), TechniqueGroup.defense);
    expect(TechniqueGroup.striking.label, 'Striking');
  });

  test('vault voegt eigen en bibliotheek samen zonder dubbelingen', () {
    const lib = [
      LibraryTechnique(id: 'harai', name: 'Harai Goshi', category: 'Takedown', subcategory: 'Throw'),
      LibraryTechnique(id: 'armbar', name: 'Armbar', category: 'Submission', subcategory: 'Armlock'),
      LibraryTechnique(id: 'jab', name: 'Jab', category: 'Strike', subcategory: 'Punch'),
    ];
    const own = [
      Technique(id: 'o1', name: 'Harai Goshi', category: 'Takedown', libraryId: 'harai', focusMode: 'next'),
      Technique(id: 'o2', name: 'armbar', category: 'Submission'), // oude rij, match op naam
      Technique(id: 'o3', name: 'Eigen worp', category: 'Takedown'),
    ];
    final v = buildVault(own, lib);
    expect(v.length, 4);
    expect(v.where((e) => e.isOwn).length, 3);
    final harai = v.firstWhere((e) => e.name == 'Harai Goshi');
    expect(harai.library?.id, 'harai');
    expect(harai.inFocus, isTrue);
    expect(v.firstWhere((e) => e.key == 'o2').library?.id, 'armbar');
    final jab = v.firstWhere((e) => e.name == 'Jab');
    expect(jab.isOwn, isFalse);
    expect(jab.key, 'lib:jab');
    expect(jab.group, TechniqueGroup.striking);
  });
}
