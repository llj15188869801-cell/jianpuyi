"""
简谱译 OCR 引擎
负责图像预处理和简谱符号识别
"""

class OCREngine:
    """简谱 OCR 识别引擎"""

    # 简谱数字到音名的映射
    NOTE_MAP = {
        '1': 'C', '2': 'D', '3': 'E', '4': 'F',
        '5': 'G', '6': 'A', '7': 'B',
        '0': 'rest', '-': 'sustain'
    }

    def __init__(self):
        self.confidence_threshold = 0.8

    def preprocess_image(self, image_bytes: bytes):
        """
        图像预处理
        1. 灰度转换
        2. 二值化
        3. 去噪
        4. 倾斜校正
        """
        # TODO: 集成 OpenCV
        # import cv2
        # import numpy as np
        # img = cv2.imdecode(np.frombuffer(image_bytes, np.uint8), cv2.IMREAD_GRAYSCALE)
        # _, binary = cv2.threshold(img, 127, 255, cv2.THRESH_BINARY)
        # return binary
        return image_bytes

    def recognize(self, image_bytes: bytes) -> dict:
        """
        识别简谱图片
        返回结构化的音符数据
        """
        processed = self.preprocess_image(image_bytes)

        # TODO: 实际的 OCR 识别逻辑
        # 当前返回模拟数据
        return {
            "notes": ["1", "1", "5", "5", "6", "6", "5", "-"],
            "key_signature": "1=C",
            "time_signature": "4/4",
            "tempo": 85,
            "confidence": 0.95
        }

    def parse_jianpu_text(self, text: str) -> list:
        """
        解析简谱文本字符串
        输入: "1 2 3 4 5 6 7"
        输出: [{'note': '1', 'pitch': 'normal', 'duration': 1.0}, ...]
        """
        notes = []
        tokens = text.strip().split()

        for token in tokens:
            if token in self.NOTE_MAP:
                notes.append({
                    'note': token,
                    'pitch': 'normal',
                    'duration': 1.0,
                    'is_rest': token in ('0', '-')
                })

        return notes

    def transpose(self, notes: list, from_key: str, to_key: str) -> list:
        """
        转调处理
        """
        key_semitones = {
            'C': 0, 'C#': 1, 'D': 2, 'D#': 3, 'E': 4, 'F': 5,
            'F#': 6, 'G': 7, 'G#': 8, 'A': 9, 'A#': 10, 'B': 11
        }

        interval = key_semitones.get(to_key, 0) - key_semitones.get(from_key, 0)
        jianpu_to_semitone = [0, 0, 2, 4, 5, 7, 9, 11]  # 1-7 对应的半音数
        semitone_to_jianpu = {0: 1, 2: 2, 4: 3, 5: 4, 7: 5, 9: 6, 11: 7}

        transposed = []
        for note_data in notes:
            note = note_data.get('note', '0')
            if note in ('0', '-'):
                transposed.append(note_data)
                continue

            try:
                n = int(note)
                if 1 <= n <= 7:
                    semitone = (jianpu_to_semitone[n] + interval) % 12
                    new_note = semitone_to_jianpu.get(semitone, n)
                    transposed.append({**note_data, 'note': str(new_note)})
                else:
                    transposed.append(note_data)
            except (ValueError, IndexError):
                transposed.append(note_data)

        return transposed
