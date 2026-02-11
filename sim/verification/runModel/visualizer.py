import os
import csv
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.colors import ListedColormap

# 경로 설정 - 이제 이 코드가 venv를 타고 scenarios.csv를 읽을 거야
current_dir = os.path.dirname(os.path.abspath(__file__))
project_root = os.path.abspath(os.path.join(current_dir, "../../../"))
CSV_PATH = os.path.join(project_root, "sim/verification/source/scenarios.csv")


def run_visualizer_pro(mem_size_words=262144):  # 2MB 영역
    print(f"🎨 시각화 엔진 가동 중... (대상: {CSV_PATH})")

    if not os.path.exists(CSV_PATH):
        print(f"❌ 에러: {CSV_PATH} 가 없습니다. generator부터 돌리세요!")
        return

    # 1. 메모리 캔버스 (512x512)
    grid_dim = int(np.sqrt(mem_size_words))
    memory_map = np.zeros(mem_size_words, dtype=int)

    # 2. 데이터 마킹 (1: 읽기 영역, 2: 쓰기 영역)
    with open(CSV_PATH, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            src_idx = int(row['src_addr'], 16) // 4
            dst_idx = int(row['dst_addr'], 16) // 4
            word_len = int(row['length']) // 4
            memory_map[src_idx: src_idx + word_len] = 1
            memory_map[dst_idx: dst_idx + word_len] = 2

    grid = memory_map.reshape((grid_dim, grid_dim))

    # 3. 그리기 (다크 모드 스타일)
    plt.style.use('dark_background')
    fig, ax = plt.subplots(figsize=(10, 8))

    # 0=어두운 회색, 1=시안(소스), 2=마젠타(목적지)
    cmap = ListedColormap(['#222222', '#00FFFF', '#FF00FF'])
    img = ax.imshow(grid, cmap=cmap, interpolation='nearest')

    plt.title("AXI4-DMA Memory Access Heatmap", fontsize=15, pad=15)
    cbar = plt.colorbar(img, ticks=[0.33, 1, 1.66])
    cbar.ax.set_yticklabels(['Empty', 'Source', 'Destination'])

    # 결과 저장
    plt.savefig(os.path.join(current_dir, "../visualization/dma_map_v2.png"))
    print("✅ 시각화 성공! dma_map_v2.png 파일을 확인해봐.")
    plt.show()


if __name__ == "__main__":
    run_visualizer_pro()