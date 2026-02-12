import struct
from PIL import Image


def convert_bin_to_png(bin_filename, png_filename):
    # 1. 파일 읽기
    with open(bin_filename, "rb") as f:
        data = f.read()

    # 2. 이미지 크기 설정 (21x21x4 = 1764 bytes)
    width, height = 21, 21

    if len(data) != width * height * 4:
        print(f"오류: 파일 크기가 {len(data)}바이트입니다. 21x21 RGBA(1764바이트)가 아닙니다.")
        return

    # 3. 바이트 재배치 (Little Endian 0xRRGGBBAA -> PIL RGBA)
    # C에서 unsigned int로 저장하면 메모리에 [AA, BB, GG, RR] 순으로 들어감
    # PIL은 [RR, GG, BB, AA] 순서를 원함
    converted_data = bytearray()
    for i in range(0, len(data), 4):
        a = data[i]
        b = data[i + 1]
        g = data[i + 2]
        r = data[i + 3]
        converted_data.extend([r, g, b, a])

    # 4. 이미지 생성 및 저장
    img = Image.frombytes("RGBA", (width, height), bytes(converted_data))
    img.save(png_filename)
    print(f"✅ 변환 완료: {png_filename}")


if __name__ == "__main__":
    convert_bin_to_png("../input/ball60_result2.bin", "../output/result_21x21_01.png")