from PIL import Image, ImageDraw

def generate_tiny_ball_header():
    # 1. 80x80 이미지 (배경: 어두운 회색)
    width, height = 80, 80
    img = Image.new('RGB', (width, height), color=(50, 50, 50))
    draw = ImageDraw.Draw(img)

    # 2. 작은 노란색 공 그리기
    # 중앙(40, 40) 기준 반지름 10 -> 지름 20
    # 좌표: (40-10, 40-10, 40+10, 40+10) -> (30, 30, 50, 50)
    draw.ellipse((30, 30, 50, 50), fill=(255, 200, 0), outline=(255, 255, 255))

    # 3. 데이터 변환 (0xRRGGBBAA)
    pixels = list(img.getdata())
    hex_data = [f"0x{(r << 24) | (g << 16) | (b << 8) | 0xFF:08X}" for r, g, b in pixels]

    # 4. 헤더 파일 생성
    with open("../output/image_data_ball_80.h", "w") as f:
        f.write("#ifndef IMAGE_DATA_BALL_H\n#define IMAGE_DATA_BALL_H\n\n")
        f.write("#define IMG_WIDTH  80\n")
        f.write("#define IMG_HEIGHT 80\n")
        f.write(f"#define BALL_SIZE  20\n\n") # 공의 실제 크기 정보 추가
        f.write(f"const unsigned int image_data_ball[{len(hex_data)}] = {{\n")
        for i in range(0, len(hex_data), 8):
            line = ", ".join(hex_data[i:i+8])
            f.write(f"    {line},\n" if i+8 < len(hex_data) else f"    {line}\n")
        f.write("};\n\n#endif")

    print("✅ 이제야 좀 볼만한 작은 공 헤더 생성 완료!")

if __name__ == "__main__":
    generate_tiny_ball_header()