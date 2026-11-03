class DiseaseDatabase {
  static const Map<String, Map<String, dynamic>> diseases = {
    // Skin/Dermascopy Diseases
    'Actinic Keratoses and Intraepithelial Carcinoma': {
      'category': 'skin',
      'description':
          'A precancerous skin condition with rough, scaly patches on sun-exposed areas. Appears as dry, rough patches that feel like sandpaper, typically pink, red, or brown in color. Can progress to skin cancer if untreated.',
      'model3d': 'assets/3d_models/actinic-keratoses.glb',
    },
    'Basal Cell Carcinoma': {
      'category': 'skin',
      'description':
          'The most common type of skin cancer, appearing as a pearly or waxy bump, often with visible blood vessels. May also present as a flat, flesh-colored or brown scar-like lesion. Grows slowly and rarely spreads.',
      'model3d': 'assets/3d_models/basal-cell-carcinoma.glb',
    },
    'Benign Keratosis-like Lesions': {
      'category': 'skin',
      'description':
          'Non-cancerous skin growths with a "pasted-on" appearance. Usually brown, black, or tan with a waxy, scaly, or rough texture. Common in older adults and generally harmless.',
      'model3d': 'assets/3d_models/seborrheic-keratosis-benign.glb',
    },
    'Dermatofibroma': {
      'category': 'skin',
      'description':
          'A harmless, firm bump under the skin, typically pink or brown in color. Often appears on the legs and may dimple inward when pinched. Usually painless but can be tender.',
      'model3d': 'assets/3d_models/dermatofibroma.glb',
    },
    'Melanocytic Nevi': {
      'category': 'skin',
      'description':
          'Common moles that are typically brown, round, and uniform in color. Most are benign and appear during childhood. Monitor for changes using the ABCDE rule (Asymmetry, Border, Color, Diameter, Evolution).',
      'model3d': 'assets/3d_models/melanocytic-nevi.glb',
    },
    'Melanoma': {
      'category': 'skin',
      'description':
          'A serious form of skin cancer originating from melanocytes. Characterized by asymmetric shape, irregular borders, multiple colors, large diameter, and evolving appearance. Early detection is crucial for successful treatment.',
      'model3d': 'assets/3d_models/melanoma.glb',
    },
    'Vascular Lesions': {
      'category': 'skin',
      'description':
          'Abnormal blood vessel growths appearing as red, purple, or blue marks on the skin. Can include hemangiomas and other vascular malformations. Most are benign and may fade over time.',
      'model3d': 'assets/3d_models/vascular-lesions.glb',
    },

    // Eye / Retinal Fundus (Diabetic Retinopathy — APTOS 2019 5-class grading)
    'No DR': {
      'category': 'eye',
      'description':
          'No diabetic retinopathy detected. Retinal vasculature appears normal. Continue annual dilated eye exams and maintain tight glycaemic control.',
    },
    'Mild DR': {
      'category': 'eye',
      'description':
          'Mild non-proliferative diabetic retinopathy. A few micro-aneurysms are present. Early stage — usually no vision loss yet, but retinopathy can progress. 6-monthly follow-up and tight HbA1c control advised.',
    },
    'Moderate DR': {
      'category': 'eye',
      'description':
          'Moderate non-proliferative diabetic retinopathy. Micro-aneurysms, dot-blot haemorrhages and/or hard exudates are present. Refer to an ophthalmologist for a retinal specialist evaluation within weeks.',
    },
    'Severe DR': {
      'category': 'eye',
      'description':
          'Severe non-proliferative diabetic retinopathy. Extensive haemorrhages, venous beading or intra-retinal microvascular abnormalities. High risk of progression to proliferative disease — urgent ophthalmology referral.',
    },
    'Proliferative DR': {
      'category': 'eye',
      'description':
          'Proliferative diabetic retinopathy. Neovascularization of the retina / optic disc with risk of vitreous haemorrhage and retinal detachment. Sight-threatening — needs urgent laser pan-retinal photocoagulation or anti-VEGF therapy.',
    },

    // Heart Sound Conditions
    'Normal Heart Sound': {
      'category': 'heart_sound',
      'description':
          'Normal cardiac sounds with no detectable abnormalities. The heart valves are functioning properly with regular rhythm and no murmurs detected.',
      'severity': 'LOW',
    },
    'Aortic Stenosis': {
      'category': 'heart_sound',
      'description':
          'Narrowing of the aortic valve restricting blood flow from the heart to the aorta. Produces a characteristic crescendo-decrescendo systolic murmur. Can lead to chest pain, fainting, and heart failure if untreated.',
      'severity': 'HIGH',
    },
    'Mitral Regurgitation': {
      'category': 'heart_sound',
      'description':
          'Backward flow of blood through the mitral valve during systole. Produces a blowing holosystolic murmur heard best at the apex. May cause fatigue, shortness of breath, and heart palpitations.',
      'severity': 'MEDIUM',
    },
    'Mitral Stenosis': {
      'category': 'heart_sound',
      'description':
          'Narrowing of the mitral valve obstructing blood flow from left atrium to left ventricle. Produces a low-pitched diastolic rumble with an opening snap. Can cause shortness of breath, fatigue, and atrial fibrillation.',
      'severity': 'HIGH',
    },
    'Mitral Valve Prolapse': {
      'category': 'heart_sound',
      'description':
          'Mitral valve leaflets bulge back into the left atrium during systole. Often produces a mid-systolic click followed by a late systolic murmur. Usually benign but may require monitoring.',
      'severity': 'LOW',
    },
  };

  static Map<String, dynamic>? getDiseaseInfo(String diseaseName) {
    return diseases[diseaseName];
  }

  static String getModelPath(String category) {
    switch (category) {
      case 'skin':
        return 'assets/models/skin_float16.tflite';
      case 'eye':
        return 'assets/models/eye_float16.tflite';
      default:
        return '';
    }
  }

  static bool isClassificationModel(String category) {
    switch (category) {
      case 'eye':
        return true; // APTOS DR grading
      default:
        return false;
    }
  }

  static List<String> getLabels(String category) {
    switch (category) {
      case 'skin':
        return [
          'Actinic Keratoses and Intraepithelial Carcinoma',
          'Basal Cell Carcinoma',
          'Benign Keratosis-like Lesions',
          'Dermatofibroma',
          'Melanocytic Nevi',
          'Melanoma',
          'Vascular Lesions',
        ];
      case 'eye':
        return [
          'No DR',
          'Mild DR',
          'Moderate DR',
          'Severe DR',
          'Proliferative DR',
        ];
      default:
        return [];
    }
  }
}
