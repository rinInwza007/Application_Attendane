#!/usr/bin/env python3
"""
สคริปต์สำหรับสร้าง TensorFlow Lite Model ง่ายๆ สำหรับการทดสอบ
"""

import tensorflow as tf
import numpy as np

def create_simple_face_model():
    """สร้าง model ง่ายๆ ที่รับ input 112x112x3 และส่งออก 128 features"""
    
    # สร้าง Sequential model
    model = tf.keras.Sequential([
        # Input layer
        tf.keras.layers.Input(shape=(112, 112, 3)),
        
        # Convolutional layers
        tf.keras.layers.Conv2D(32, (3, 3), activation='relu', padding='same'),
        tf.keras.layers.MaxPooling2D((2, 2)),
        
        tf.keras.layers.Conv2D(64, (3, 3), activation='relu', padding='same'),
        tf.keras.layers.MaxPooling2D((2, 2)),
        
        tf.keras.layers.Conv2D(128, (3, 3), activation='relu', padding='same'),
        tf.keras.layers.MaxPooling2D((2, 2)),
        
        # Global average pooling
        tf.keras.layers.GlobalAveragePooling2D(),
        
        # Dense layers
        tf.keras.layers.Dense(256, activation='relu'),
        tf.keras.layers.Dropout(0.5),
        tf.keras.layers.Dense(128, activation=None),  # No activation for embeddings
        
        # L2 normalization
        tf.keras.layers.Lambda(lambda x: tf.nn.l2_normalize(x, axis=1))
    ])
    
    return model

def convert_to_tflite(model, output_path):
    """แปลง Keras model เป็น TensorFlow Lite"""
    
    # สร้าง converter
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    
    # เพิ่ม optimization
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    
    # แปลงเป็น TFLite
    tflite_model = converter.convert()
    
    # บันทึกไฟล์
    with open(output_path, 'wb') as f:
        f.write(tflite_model)
    
    print(f"✅ TensorFlow Lite model saved to: {output_path}")
    print(f"📊 Model size: {len(tflite_model)} bytes")

def test_model(model_path):
    """ทดสอบ model ที่สร้างขึ้น"""
    
    # โหลด TFLite model
    interpreter = tf.lite.Interpreter(model_path=model_path)
    interpreter.allocate_tensors()
    
    # ดูข้อมูล input/output
    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()
    
    print("\n📊 Model Information:")
    print(f"Input shape: {input_details[0]['shape']}")
    print(f"Input dtype: {input_details[0]['dtype']}")
    print(f"Output shape: {output_details[0]['shape']}")
    print(f"Output dtype: {output_details[0]['dtype']}")
    
    # ทดสอบด้วยข้อมูลสุ่ม
    test_input = np.random.random((1, 112, 112, 3)).astype(np.float32)
    
    interpreter.set_tensor(input_details[0]['index'], test_input)
    interpreter.invoke()
    
    output = interpreter.get_tensor(output_details[0]['index'])
    
    print(f"\n🧪 Test Results:")
    print(f"Output shape: {output.shape}")
    print(f"Output sample: {output[0][:5]}")
    print(f"Output magnitude: {np.linalg.norm(output[0]):.6f}")
    
    return True

if __name__ == "__main__":
    print("🔄 Creating simple face recognition model...")
    
    # สร้าง model
    model = create_simple_face_model()
    
    # แสดงสรุป model
    model.summary()
    
    # บันทึกเป็น TFLite
    output_path = "converted_model.tflite"
    convert_to_tflite(model, output_path)
    
    # ทดสอบ model
    test_model(output_path)
    
    print("\n✅ Simple face recognition model created successfully!")
    print(f"📁 Copy this file to your Flutter project: assets/{output_path}")