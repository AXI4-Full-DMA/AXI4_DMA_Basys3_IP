import struct
from PIL import Image


def convert_bin_to_png(bin_file, output_png, width, height):
    # 1. 바이너리 파일 읽기
    try:
        with open(bin_file, 'rb') as f:
            data = f.read()
    except FileNotFoundError:
        print(f"❌ 에러: {bin_file} 파일을 찾을 수 없습니다.")
        return

    # 2. 픽셀 데이터 변환 (32-bit HEX -> RGB)
    # AXI DMA에서 뽑은 데이터는 보통 Little Endian (AA BB GG RR) 순서입니다.
    pixels_rgb = []
    num_pixels = len(data) // 4

    print(f"📊 읽은 데이터: {len(data)} 바이트 ({num_pixels} 픽셀)")

    for i in range(num_pixels):
        # 4바이트씩 끊어서 읽음
        chunk = data[i * 4: (i + 1) * 4]
        # Little Endian 기준: [0]=Alpha, [1]=Blue, [2]=Green, [3]=Red
        # 만약 색상이 이상하면 아래 인덱스 순서를 r, g, b = chunk[0], chunk[1], chunk[2] 로 바꿔보세요.
        a = chunk[0]
        b = chunk[1]
        g = chunk[2]
        r = chunk[3]
        pixels_rgb.append((r, g, b))

    # 3. 이미지 생성 및 저장
    if len(pixels_rgb) < width * height:
        print(f"⚠️ 경고: 데이터가 부족합니다. (필요: {width * height}, 실제: {len(pixels_rgb)})")
        # 부족한 부분은 검은색으로 채움
        pixels_rgb += [(0, 0, 0)] * (width * height - len(pixels_rgb))

    img = Image.new('RGB', (width, height))
    img.putdata(pixels_rgb[:width * height])  # 정해진 크기만큼만 잘라서 넣음
    img.save(output_png)
    print(f"✅ 이미지 저장 완료: {output_png} ({width}x{height})")


if __name__ == "__main__":
    # --- 설정값 ---
    input_file = "../input/ball_result (1).bin"  # 형님이 주신 파일명
    output_name = "result_image.png"
    img_w = 80  # 노란 공 가로 크기
    img_h = 80  # 노란 공 세로 크기
    # --------------

    convert_bin_to_png(input_file, output_name, img_w, img_h)