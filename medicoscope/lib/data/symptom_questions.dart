import 'package:medicoscope/core/constants/disease_constants.dart';

class SymptomQuestion {
  final String id;
  final String text;
  final double weight; // 0.0–1.0, relative contribution to score
  final List<String> redFlags; // additional terms that push to critical if mentioned

  const SymptomQuestion({
    required this.id,
    required this.text,
    this.weight = 1.0,
    this.redFlags = const [],
  });
}

class SymptomQuestionBank {
  static const Map<DiseaseType, List<SymptomQuestion>> byDisease = {
    DiseaseType.diabetes: [
      SymptomQuestion(
          id: 'thirst',
          text: 'Are you frequently thirsty, even after drinking water?',
          weight: 1.0),
      SymptomQuestion(
          id: 'urination',
          text: 'Do you urinate more than 6–7 times a day or wake up at night?',
          weight: 1.0),
      SymptomQuestion(
          id: 'fatigue',
          text: 'Do you feel unusually tired or fatigued during the day?',
          weight: 0.7),
      SymptomQuestion(
          id: 'blurred_vision',
          text: 'Have you noticed blurred or changing vision recently?',
          weight: 0.8),
      SymptomQuestion(
          id: 'slow_healing',
          text: 'Do cuts or bruises take longer than usual to heal?',
          weight: 0.9),
      SymptomQuestion(
          id: 'weight_loss',
          text: 'Have you lost weight without trying?',
          weight: 0.7,
          redFlags: ['unexplained']),
      SymptomQuestion(
          id: 'family_history',
          text: 'Does a parent or sibling have diabetes?',
          weight: 0.6),
      SymptomQuestion(
          id: 'tingling',
          text: 'Do you feel tingling or numbness in hands or feet?',
          weight: 0.8),
    ],
    DiseaseType.hypertension: [
      SymptomQuestion(
          id: 'headache',
          text: 'Do you get frequent headaches, especially in the mornings?',
          weight: 0.9),
      SymptomQuestion(
          id: 'dizziness',
          text: 'Do you experience dizziness or lightheadedness?',
          weight: 0.8),
      SymptomQuestion(
          id: 'chest_pain',
          text: 'Any chest pain, pressure, or tightness?',
          weight: 1.0,
          redFlags: ['radiating', 'crushing', 'left arm']),
      SymptomQuestion(
          id: 'breathlessness',
          text: 'Do you get short of breath doing mild activity?',
          weight: 0.9),
      SymptomQuestion(
          id: 'palpitations',
          text: 'Do you notice an irregular or fast heartbeat?',
          weight: 0.8),
      SymptomQuestion(
          id: 'high_salt',
          text: 'Is your daily diet high in salty or processed foods?',
          weight: 0.6),
      SymptomQuestion(
          id: 'family_history',
          text: 'Is there a family history of hypertension or stroke?',
          weight: 0.7),
      SymptomQuestion(
          id: 'stress',
          text: 'Do you feel chronically stressed or anxious?',
          weight: 0.6),
    ],
    DiseaseType.anemia: [
      SymptomQuestion(
          id: 'fatigue',
          text: 'Do you feel constantly tired, even after rest?',
          weight: 1.0),
      SymptomQuestion(
          id: 'pallor',
          text: 'Do people mention that you look pale?',
          weight: 0.9),
      SymptomQuestion(
          id: 'breathlessness',
          text: 'Do you get breathless climbing a single flight of stairs?',
          weight: 0.9),
      SymptomQuestion(
          id: 'cold_hands',
          text: 'Are your hands and feet frequently cold?',
          weight: 0.7),
      SymptomQuestion(
          id: 'dizziness',
          text: 'Do you feel dizzy when standing up quickly?',
          weight: 0.7),
      SymptomQuestion(
          id: 'brittle_nails',
          text: 'Have your nails become brittle or spoon-shaped?',
          weight: 0.6),
      SymptomQuestion(
          id: 'heavy_periods',
          text: 'Do you experience heavy menstrual bleeding (if applicable)?',
          weight: 0.9),
      SymptomQuestion(
          id: 'diet_iron',
          text: 'Is your diet low in iron-rich foods (leafy greens, meat, pulses)?',
          weight: 0.6),
    ],
  };
}
