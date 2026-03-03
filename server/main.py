from fastapi import FastAPI, UploadFile, File
import uvicorn

app = FastAPI(title="简谱译 OCR Server", version="1.1.0")

@app.get("/")
async def root():
    return {"message": "简谱译 OCR 服务运行中", "version": "1.1.0"}

@app.post("/translate")
async def translate_notation(file: UploadFile = File(...)):
    """
    接收简谱图片，返回识别结果
    1. 接收图片
    2. 调用 OpenCV 识别 1 2 3 4 5 6 7
    3. 返回 JSON 数据
    """
    contents = await file.read()
    file_size = len(contents)

    # 模拟识别结果
    mock_result = {
        "status": "success",
        "file_size": file_size,
        "notes": ["1", "1", "5", "5", "6", "6", "5", "-", "4", "4", "3", "3", "2", "2", "1", "-"],
        "key": "C Major",
        "tempo": 85,
        "confidence": 0.95
    }
    return mock_result

@app.post("/transpose")
async def transpose_notation(notes: list, from_key: str = "C", to_key: str = "G"):
    """
    转调功能
    将音符从一个调转换到另一个调
    """
    key_map = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
    interval = key_map.get(to_key, 0) - key_map.get(from_key, 0)

    transposed = []
    for note in notes:
        if note == "-" or note == "0":
            transposed.append(note)
        else:
            try:
                n = int(note)
                new_n = ((n - 1 + interval) % 7) + 1
                transposed.append(str(new_n))
            except ValueError:
                transposed.append(note)

    return {
        "status": "success",
        "original_key": from_key,
        "target_key": to_key,
        "original_notes": notes,
        "transposed_notes": transposed
    }

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
