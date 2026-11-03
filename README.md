# \# \\# MedicoScope - Medical AI Assistant

# 

# \# 

# 

# \# A professional Flutter medical imaging application providing AI-powered analysis for patients and assistive diagnostics for doctors.

# 

# \# 

# 

# \# !\\\[Flutter](https://img.shields.io/badge/Flutter-3.6.0-02569B?logo=flutter)

# 

# \# !\\\[Dart](https://img.shields.io/badge/Dart-3.6.0-0175C2?logo=dart)

# 

# \# !\\\[License](https://img.shields.io/badge/License-MIT-green)

# 

# \# 

# 

# \# \\## ✨ Features

# 

# \# 

# 

# \# \\- 🎨 \\\*\\\*Beautiful UI/UX\\\*\\\* - Glassmorphism design with smooth animations

# 

# \# \\- 🤖 \\\*\\\*AI-Powered Analysis\\\*\\\* - YOLOv8s TFLite models for medical image detection

# 

# \# \\- 📸 \\\*\\\*Image Capture\\\*\\\* - Camera and gallery support

# 

# \# \\- 🧬 \\\*\\\*4 Medical Categories\\\*\\\* - Skin, Eye, Chest X-Ray, Brain MRI

# 

# \# \\- 🎭 \\\*\\\*3D Visualization\\\*\\\* - Interactive 3D models of detected conditions

# 

# \# \\- 📱 \\\*\\\*Cross-Platform\\\*\\\* - Android, iOS ready

# 

# \# 

# 

# \# \\## 🚀 Quick Start

# 

# \# 

# 

# \# \\### Prerequisites

# 

# \# 

# 

# \# \\- Flutter SDK 3.6.0 or higher

# 

# \# \\- Dart SDK 3.6.0 or higher

# 

# \# \\- Android Studio / Xcode (for mobile development)

# 

# \# 

# 

# \# \\### Installation

# 

# \# 

# 

# \# 1\\. \\\*\\\*Clone the repository\\\*\\\*

# 

# \# \&nbsp;  ```bash

# 

# \# \&nbsp;  cd "d:\\\\Aavishkar 2026\\\\MedicoScope"

# 

# \# \&nbsp;  ```

# 

# \# 

# 

# \# 2\\. \\\*\\\*Install dependencies\\\*\\\* (Already done)

# 

# \# \&nbsp;  ```bash

# 

# \# \&nbsp;  flutter pub get

# 

# \# \&nbsp;  ```

# 

# \# 

# 

# \# 3\\. \\\*\\\*Add TFLite Models\\\*\\\* (Already done)

# 

# \# \&nbsp;  

# 

# \# \&nbsp;  Place your YOLOv8s `.tflite` files in:

# 

# \# \&nbsp;  ```

# 

# \# \&nbsp;  assets/models/

# 

# \# \&nbsp;  ├── skin\\\_float16.tflite

# 

# \# \&nbsp;  ├── eye\\\_float16.tflite

# 

# \# \&nbsp;  ├── chest\\\_float16.tflite

# 

# \# \&nbsp;  └── brain\\\_float16.tflite

# 

# \# \&nbsp;  ```

# 

# \# 

# 

# \# 4\\. \\\*\\\*Add 3D Models\\\*\\\* (Optional)

# 

# \# \&nbsp;  

# 

# \# \&nbsp;  Place your `.glb` 3D model files in:

# 

# \# \&nbsp;  ```

# 

# \# \&nbsp;  assets/3d\\\_models/

# 

# \# \&nbsp;  ├── skin/

# 

# \# \&nbsp;  ├── eye/

# 

# \# \&nbsp;  ├── chest/

# 

# \# \&nbsp;  └── brain/

# 

# \# \&nbsp;  ```

# 

# \# 

# 

# \# 5\\. \\\*\\\*Run the app\\\*\\\*

# 

# \# \&nbsp;  ```bash

# 

# \# \&nbsp;  flutter run

# 

# \# \&nbsp;  ```

# 

# \# 

# 

# \# \\## 📱 Supported Platforms

# 

# \# 

# 

# \# \\- ✅ Android

# 

# \# \\- ✅ iOS

# 

# \# \\- ⚠️ Web (limited 3D support)

# 

# \# 

# 

# \# \\## 🎨 UI/UX Design

# 

# \# 

# 

# \# The app features a modern, professional design with:

# 

# \# \\- \\\*\\\*Glassmorphism effects\\\*\\\* - Frosted glass cards with backdrop blur

# 

# \# \\- \\\*\\\*Orange accent colors\\\*\\\* - Matching medical/health theme

# 

# \# \\- \\\*\\\*Inter font family\\\*\\\* - Clean, modern typography

# 

# \# \\- \\\*\\\*Smooth animations\\\*\\\* - 400-600ms transitions with eased curves

# 

# \# \\- \\\*\\\*Category-specific gradients\\\*\\\* - Unique colors for each medical type

# 

# \# 

# 

# \# \\## 🏗️ Architecture

# 

# \# 

# 

# \# ```

# 

# \# lib/

# 

# \# ├── core/           # Theme, widgets, utilities

# 

# \# ├── data/           # Disease database

# 

# \# ├── models/         # Data models

# 

# \# ├── screens/        # UI screens

# 

# \# ├── services/       # TFLite, AR services

# 

# \# └── main.dart       # App entry point

# 

# \# ```

# 

# \# 

# 

# \# \\## 📋 Medical Categories

# 

# \# 

# 

# \# \\### 1. Skin / Dermascopy (7 conditions)

# 

# \# \\- Actinic Keratoses

# 

# \# \\- Basal Cell Carcinoma

# 

# \# \\- Benign Keratosis

# 

# \# \\- Dermatofibroma

# 

# \# \\- Melanocytic Nevi

# 

# \# \\- Melanoma

# 

# \# \\- Vascular Lesions

# 

# \# 

# 

# \# \\### 2. Eye / Fundus (1 condition)

# 

# \# \\- Red Lesions (Retinal Hemorrhages)

# 

# \# 

# 

# \# \\### 3. Chest X-Ray (8 conditions)

# 

# \# \\- Atelectasis

# 

# \# \\- Cardiomegaly

# 

# \# \\- Effusion

# 

# \# \\- Infiltrate

# 

# \# \\- Mass

# 

# \# \\- Nodule

# 

# \# \\- Pneumonia

# 

# \# \\- Pneumothorax

# 

# \# 

# 

# \# \\### 4. Brain MRI (1 condition)

# 

# \# \\- Tumor-Cell (Glioma)

# 

# \# 

# 

# \# \\## 🔧 Configuration

# 

# \# 

# 

# \# \\### Camera Permissions

# 

# \# 

# 

# \# \\\*\\\*Android\\\*\\\* (`android/app/src/main/AndroidManifest.xml`):

# 

# \# ```xml

# 

# \# <uses-permission android:name="android.permission.CAMERA"/>

# 

# \# <uses-permission android:name="android.permission.READ\\\_EXTERNAL\\\_STORAGE"/>

# 

# \# ```

# 

# \# 

# 

# \# \\\*\\\*iOS\\\*\\\* (`ios/Runner/Info.plist`):

# 

# \# ```xml

# 

# \# <key>NSCameraUsageDescription</key>

# 

# \# <string>We need camera access to capture medical images</string>

# 

# \# <key>NSPhotoLibraryUsageDescription</key>

# 

# \# <string>We need photo library access to select medical images</string>

# 

# \# ```

# 

# \# 

# 

# \# \\## 📦 Dependencies

# 

# \# 

# 

# \# | Package | Version | Purpose |

# 

# \# |---------|---------|---------|

# 

# \# | tflite\\\_flutter | 0.10.4 | TFLite inference |

# 

# \# | image\\\_picker | 1.2.0 | Camera/gallery |

# 

# \# | model\\\_viewer\\\_plus | 1.9.2 | 3D models |

# 

# \# | flutter\\\_animate | 4.5.2 | Animations |

# 

# \# | google\\\_fonts | 6.3.0 | Typography |

# 

# \# 

# 

# \# \\## 🎯 Usage Flow

# 

# \# 

# 

# \# 1\\. \\\*\\\*Onboarding\\\*\\\* - Interactive tutorial explaining features

# 

# \# 2\\. \\\*\\\*Welcome\\\*\\\* - App introduction and purpose

# 

# \# 3\\. \\\*\\\*Category Selection\\\*\\\* - Choose medical analysis type

# 

# \# 4\\. \\\*\\\*Image Upload\\\*\\\* - Capture or select image

# 

# \# 5\\. \\\*\\\*Analysis\\\*\\\* - AI processes the image

# 

# \# 6\\. \\\*\\\*Results\\\*\\\* - View detection with 3D model

# 

# \# 

# 

# \# \\## ⚠️ Important Notes

# 

# \# 

# 

# \# \\- TFLite models must be YOLOv8s format (640x640 input) for object detection

# 

# \# \\- Eye model uses classification, others use object detection

# 

# \# \\- Currently using demo `heart.glb` for all 3D visualizations

# 

# \# \\- AR viewing requires iOS 12+ or ARCore-compatible Android device

# 

# \# \\- Test on physical devices for best performance

# 

# \# \\- This is an assistive tool, not a replacement for professional medical diagnosis

# 

# \# 

# 

# \# \\## 📄 License

# 

# \# 

# 

# \# This project is licensed under the MIT License.

# 

# \# 

# 

# \# \\## 🤝 Contributing

# 

# \# 

# 

# \# Contributions are welcome! Please feel free to submit a Pull Request.

# 

# \# 

# 

# \# \\## 📧 Contact

# 

# \# 

# 

# \# For questions or support, please open an issue in the repository.

# 

# \# 

# 

# \# ---

# 

# \# 

# 

# \# \\\*\\\*Built with ❤️ using Flutter\\\*\\\*

# 

# 

# 



