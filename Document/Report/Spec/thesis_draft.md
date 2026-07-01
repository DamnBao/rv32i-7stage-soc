# TÓM TẮT {#tomtat .unnumbered}

Khóa luận này trình bày quá trình thiết kế và kiểm chứng một hệ thống
trên chip (SoC) dựa trên kiến trúc tập lệnh RISC-V mở, nhằm mục tiêu
nghiên cứu và học thuật. Hệ thống bao gồm lõi vi xử lý RV32I+Zicsr với
kiến trúc pipeline 7 tầng hoạt động ở tần số 1 GHz, tích hợp bộ nhớ SRAM
nội bộ (IMEM 64 KB và DMEM 64 KB), giao thức bus AXI4-Lite (1 GHz) và
AHB-Lite (500 MHz), cùng cơ chế đồng bộ hóa qua biên miền xung nhịp
(CDC) bằng FIFO bất đồng bộ với con trỏ Gray code. Hệ thống ngắt bao gồm
PLIC 6 nguồn tương thích chuẩn SiFive và khối Zicsr xử lý ngắt/ngoại lệ
M-mode. Toàn bộ RTL được viết bằng SystemVerilog có thể tổng hợp và mô
phỏng bằng Icarus Verilog.

Quá trình kiểm chứng được tổ chức thành nhiều pha tăng dần về độ phức
tạp: từ unit test (hơn 430 test case), integration test (163 test case),
system test (37 chương trình), đến bộ kiểm thử tuân thủ chính thức
riscv-arch-test. Kết quả: tất cả test case PASS và đạt 37/38 PASS trong
bộ kiểm thử tuân thủ RV32I (một bài SKIP do giới hạn kích thước code của
framework). Trong quá trình kiểm thử, năm bug RTL quan trọng được phát
hiện và sửa chữa, bao gồm gap-4 RAW hazard, IMEM stall mismatch, CSR-use
hazard stall, ghost instruction sau flush, và bus stall kết hợp load-use
hazard.

**Từ khóa** --- RISC-V, SoC, pipeline, AXI-Lite, AHB-Lite, CDC, PLIC,
SystemVerilog, kiểm chứng RTL.

::: center
**ABSTRACT**
:::

This thesis presents the design and verification of a RISC-V-based
System-on-Chip (SoC) for academic research purposes. The system features
an RV32I+Zicsr processor with a 7-stage in-order pipeline targeting
1 GHz, integrated with on-chip SRAM (64 KB IMEM and 64 KB DMEM),
AXI4-Lite (1 GHz) and AHB-Lite (500 MHz) bus interfaces, and safe Clock
Domain Crossing (CDC) via asynchronous FIFO with Gray-code pointers. The
interrupt subsystem includes a SiFive-compatible 6-source PLIC and a
Zicsr block handling M-mode exceptions and interrupts. All RTL is
written in synthesizable SystemVerilog and simulated using Icarus
Verilog.

Verification follows a multi-level strategy: unit tests (430+ test
cases), integration tests (163 test cases), system-level programs (37
programs), and the official riscv-arch-test compliance suite. All test
cases pass, and 37/38 RV32I compliance tests pass (one SKIP due to
framework code-size limitations). Five RTL bugs were discovered and
fixed during testing, including gap-4 RAW hazard, IMEM stall mismatch,
CSR-use hazard stall, ghost instruction after flush, and a concurrent
bus-stall/load-use hazard interaction.

**Keywords** --- RISC-V, SoC, pipeline, AXI-Lite, AHB-Lite, CDC, PLIC,
SystemVerilog, RTL verification.

# GIỚI THIỆU {#Chapter1}

## Bối Cảnh và Động Lực Nghiên Cứu

Trong bối cảnh ngành công nghiệp vi điện tử đang phát triển nhanh chóng,
xu hướng thiết kế phần cứng mở (open-source hardware) ngày càng được
quan tâm rộng rãi. Kiến trúc tập lệnh RISC-V (Reduced Instruction Set
Computer -- Version 5), ra đời tại Đại học California, Berkeley vào năm
2010, đã trở thành một trong những nền tảng quan trọng nhất trong xu
hướng này [@riscv-spec]. Khác với các kiến trúc thương mại như ARM hay
x86, RISC-V hoàn toàn mở, không thu phí bản quyền và được quản lý bởi tổ
chức phi lợi nhuận RISC-V International. Điều này tạo điều kiện thuận
lợi để các cơ sở học thuật và doanh nghiệp có thể tự do nghiên cứu,
triển khai và tùy chỉnh kiến trúc theo nhu cầu cụ thể.

Theo báo cáo thị trường của Semico Research, số lõi vi xử lý RISC-V được
tích hợp vào sản phẩm thương mại dự kiến đạt 62 tỷ đơn vị vào năm 2025
[@semico-riscv-growth]. Sự phát triển vượt bậc này được thúc đẩy bởi nhu
cầu ngày càng cao về các hệ thống nhúng hiệu suất cao, tiêu thụ điện
năng thấp, và có thể tùy chỉnh linh hoạt -- từ các thiết bị IoT nhỏ gọn
đến các hệ thống xử lý dữ liệu phức tạp trong trung tâm dữ liệu. Trong
bối cảnh đó, việc nghiên cứu và thiết kế một hệ thống trên chip
([soc]{acronym-label="soc" acronym-form="singular+full"}) hoàn chỉnh dựa
trên RISC-V có giá trị học thuật và thực tiễn cao.

Thiết kế một SoC không chỉ đòi hỏi việc xây dựng lõi vi xử lý mà còn bao
gồm tích hợp các giao thức bus công nghiệp chuẩn để kết nối với ngoại
vi, xử lý ngắt và ngoại lệ, đồng bộ hóa giữa các miền xung nhịp khác
nhau, và kiểm chứng toàn diện để đảm bảo tính đúng đắn của thiết kế. Đây
là những kỹ năng thiết yếu trong quy trình thiết kế vi mạch tích hợp
([asic]{acronym-label="asic" acronym-form="singular+abbrv"}/FPGA) hiện
đại.

## Mục Tiêu và Phạm Vi

Khóa luận này đặt ra mục tiêu thiết kế và kiểm chứng một hệ thống SoC
hoàn chỉnh dựa trên kiến trúc RISC-V, bao gồm:

1.  **Lõi CPU:** Xây dựng vi xử lý RV32I với phần mở rộng Zicsr theo đặc
    tả RISC-V, tổ chức theo kiến trúc pipeline 7 tầng với tần số mục
    tiêu 1 GHz.

2.  **Tích hợp bus chuẩn công nghiệp:** Kết nối CPU với ngoại vi thông
    qua hai giao thức bus -- AXI4-Lite (AMBA 4.0) và AHB-Lite (AMBA 3.0)
    -- đại diện cho hai tiêu chuẩn phổ biến nhất trong thiết kế SoC hiện
    đại [@amba-axi-spec; @amba-ahb-spec].

3.  **Xử lý đa miền xung nhịp:** Triển khai cơ chế Clock Domain Crossing
    ([cdc]{acronym-label="cdc" acronym-form="singular+abbrv"}) sử dụng
    FIFO bất đồng bộ với con trỏ Gray code để truyền dữ liệu an toàn
    giữa miền 1 GHz và 500 MHz.

4.  **Hệ thống ngắt và ngoại lệ:** Triển khai
    [plic]{acronym-label="plic" acronym-form="singular+full"} tương
    thích chuẩn SiFive và khối Zicsr xử lý ngắt/ngoại lệ M-mode theo đặc
    tả RISC-V Privileged Architecture [@riscv-priv-spec].

5.  **Kiểm chứng toàn diện:** Xây dựng môi trường kiểm thử nhiều lớp và
    đạt chuẩn tuân thủ bộ kiểm thử chính thức RV32I của tổ chức RISC-V
    International [@riscv-arch-test].

Phạm vi thiết kế giới hạn ở mức RTL (Register Transfer Level) sử dụng
ngôn ngữ SystemVerilog có thể tổng hợp. Toàn bộ mô phỏng được thực hiện
bằng công cụ Icarus Verilog 12 [@icarus-verilog].

## Phương Pháp Thực Hiện

Quy trình thiết kế và kiểm chứng trong khóa luận này theo mô hình phát
triển từ trên xuống (top-down) kết hợp kiểm chứng từ dưới lên (bottom-up
verification):

-   **Pha 1 -- Đặc tả:** Xác định kiến trúc hệ thống, bản đồ bộ nhớ,
    giao thức bus và các yêu cầu chức năng chi tiết.

-   **Pha 2 -- Thiết kế RTL:** Viết các module SystemVerilog theo từng
    khối chức năng, tuân thủ các quy tắc coding cho synthesizable design
    và yêu cầu của công cụ mô phỏng.

-   **Pha 3 -- Kiểm chứng phân cấp:** Bắt đầu từ unit test từng module,
    tiếp theo là integration test các subsystem, và system test toàn bộ
    SoC với nhiều chương trình thử nghiệm khác nhau.

-   **Pha 4 -- Kiểm thử tuân thủ:** Sử dụng bộ kiểm thử chính thức
    riscv-arch-test để xác nhận tính tuân thủ đặc tả RV32I.

## Các Công Cụ Sử Dụng

Bảng [1.1](#tab:tools){reference-type="ref" reference="tab:tools"} liệt
kê các công cụ phần mềm chính được sử dụng trong quá trình thực hiện
khóa luận.

::: center
::: {#tab:tools}
  **Công cụ**               **Phiên bản**         **Mục đích**
  ------------------------- --------------------- ----------------------------------
  Icarus Verilog            12                    Mô phỏng RTL SystemVerilog
  riscv64-unknown-elf-gcc   13.2.0                Biên dịch chương trình RISC-V
  GTKWave                   3.3.x                 Xem dạng sóng (waveform) VCD
  riscv-arch-test           2.x (old-framework)   Bộ kiểm thử tuân thủ RV32I
  GNU Make                  4.x                   Tự động hóa quy trình build/test

  : Công cụ phần mềm sử dụng trong dự án
:::
:::

## Cấu Trúc Khóa Luận

Nội dung khóa luận được tổ chức thành sáu chương, trình bày tuần tự từ
bối cảnh nghiên cứu, tổng quan lý thuyết, thiết kế, triển khai thực
nghiệm đến phân tích, đánh giá kết quả và kết luận. Cụ thể:

-   **Chương 1 -- Giới thiệu:** Trình bày bối cảnh nghiên cứu, động lực
    thực hiện đề tài, mục tiêu, phạm vi, công cụ sử dụng và tóm lược cấu
    trúc toàn khóa luận.

-   **Chương 2 -- Tổng quan nghiên cứu:** Điểm qua các dự án RISC-V SoC
    tiêu biểu trong và ngoài nước, phân tích điểm tương đồng và khác
    biệt so với thiết kế đề xuất.

-   **Chương 3 -- Cơ sở lý thuyết:** Trình bày nền tảng lý thuyết về
    kiến trúc tập lệnh RISC-V, kỹ thuật pipeline, các giao thức bus
    AXI-Lite và AHB-Lite, cơ chế CDC và xử lý ngắt.

-   **Chương 4 -- Thiết kế và triển khai hệ thống:** Mô tả chi tiết kiến
    trúc và cách triển khai từng thành phần của SoC, bao gồm pipeline
    CPU, bus interface, CDC, PLIC và Zicsr.

-   **Chương 5 -- Kết quả thực nghiệm:** Trình bày môi trường kiểm thử,
    phân tích kết quả từng pha kiểm thử, phân tích dạng sóng minh họa và
    đánh giá tổng thể hiệu quả thiết kế.

-   **Chương 6 -- Kết luận:** Tóm tắt kết quả đạt được, nêu hạn chế và
    đề xuất hướng phát triển tiếp theo.

Bên cạnh đó, khóa luận còn đính kèm phần **Tài liệu tham khảo** ở cuối
nhằm cung cấp thông tin chi tiết cho việc tra cứu.

# TỔNG QUAN NGHIÊN CỨU {#Chapter2}

## Các Dự Án RISC-V SoC Tiêu Biểu

Kể từ khi đặc tả RISC-V được công bố mở năm 2014, một số lượng lớn các
dự án thiết kế SoC dựa trên RISC-V đã xuất hiện từ các tổ chức học
thuật, công ty công nghiệp và cộng đồng mã nguồn mở. Việc khảo sát các
dự án này cung cấp nền tảng để định vị thiết kế của khóa luận trong bức
tranh tổng thể của lĩnh vực.

### SiFive FE310 và HiFive1

SiFive, công ty khởi nghiệp được sáng lập bởi các nhà nghiên cứu RISC-V
từ UC Berkeley, đã phát triển dòng vi xử lý Freedom E310 (FE310) -- một
trong những SoC thương mại đầu tiên dựa trên RISC-V [@sifive-fe310].
FE310 sử dụng lõi E31 với pipeline 5 tầng, kiến trúc RV32IMAC, và được
tích hợp trên board phát triển HiFive1. Đặc điểm nổi bật của FE310 bao
gồm PLIC (Platform-Level Interrupt Controller) tương thích đặc tả
SiFive, CLINT (Core Local Interruptor), và các ngoại vi SPI/UART/GPIO.
Tuy nhiên, FE310 sử dụng giao thức TileLink thay vì AMBA AXI/AHB, nên
không trực tiếp tương thích với hệ sinh thái ngoại vi AMBA phổ biến.

### Dự Án OpenTitan

OpenTitan là dự án nguồn mở của Google và các đối tác công nghiệp, nhằm
tạo ra một Root of Trust chip theo thiết kế mở [@opentitan]. OpenTitan
sử dụng lõi Ibex (dựa trên RI5CY) và giao thức bus TileLink-UL cho kết
nối nội bộ. Điểm đáng chú ý của OpenTitan là hệ thống quản lý thanh ghi
ngoại vi (SFR -- Special Function Register) được chuẩn hóa theo
OpenTitan Register Tool, cung cấp giao diện nhất quán cho mọi ngoại vi.
Thiết kế đề xuất trong khóa luận này lấy cảm hứng từ cách tổ chức thanh
ghi của OpenTitan để xây dựng SFR Standard Register Map.

### VexRiscv

VexRiscv là một vi xử lý RISC-V linh hoạt được viết bằng SpinalHDL, được
thiết kế theo kiến trúc plugin cho phép tùy chỉnh sâu pipeline và tính
năng [@vexriscv]. VexRiscv hỗ trợ từ pipeline 2 tầng đơn giản đến
pipeline 5 tầng đầy đủ với cache L1 và MMU. Giao thức bus sử dụng
WishBone hoặc AXI4. Điểm khác biệt so với thiết kế trong khóa luận là
VexRiscv không hỗ trợ AHB-Lite natively và không tích hợp CDC cho đa
miền xung nhịp.

### PicoRV32

PicoRV32 là một lõi RISC-V RV32IMC nhỏ gọn, được viết thuần túy bằng
Verilog và tối ưu cho FPGA [@picorv32]. PicoRV32 sử dụng kiến trúc không
pipeline (hay pipeline tối giản), ưu tiên tính đơn giản và tài nguyên
phần cứng thấp. Giao thức bus riêng của nó (PicoRV32 Memory Interface)
không tương thích với AMBA. Thiết kế này phù hợp cho các ứng dụng nhúng
cực nhỏ nhưng không phù hợp cho các hệ thống yêu cầu hiệu suất cao và
kết nối ngoại vi phong phú.

### Các Dự Án Học Thuật Khác

Trong giới học thuật, nhiều trường đại học đã công bố thiết kế RISC-V
SoC như một phần của nghiên cứu. Điển hình là BOOM (Berkeley
Out-of-Order Machine) từ UC Berkeley -- một vi xử lý RISC-V 64-bit
out-of-order phức tạp phục vụ nghiên cứu về vi kiến trúc hiệu suất cao
[@boom]. Tuy nhiên, BOOM tập trung vào nghiên cứu kiến trúc thuần túy và
không đặt trọng tâm vào tích hợp bus chuẩn công nghiệp hay kiểm chứng đa
miền xung nhịp. Bài báo [@riscv-survey] cung cấp một khảo sát toàn diện
về các triển khai và mở rộng RISC-V tính đến năm 2023.

## So Sánh Với Thiết Kế Đề Xuất

Bảng [2.1](#tab:comparison){reference-type="ref"
reference="tab:comparison"} so sánh đặc điểm thiết kế của các dự án tiêu
biểu với thiết kế được đề xuất trong khóa luận này.

::: center
::: {#tab:comparison}
  **Đặc điểm**        **FE310**   **VexRiscv**   **PicoRV32**   **OpenTitan**      **Đề xuất**
  ------------------ ----------- -------------- -------------- --------------- -------------------
  ISA                 RV32IMAC    RV32I/IM(A)      RV32IMC          RV32I          RV32I+Zicsr
  Pipeline             5 tầng      2--5 tầng        Không          2 tầng          **7 tầng**
  Bus AXI-Lite          Không          Có           Không           Không            **Có**
  Bus AHB-Lite          Không        Không          Không           Không            **Có**
  CDC đa miền           Không        Không          Không           Không         **Có (FIFO)**
  PLIC tích hợp          Có         Tùy chọn        Không            Có         **Có (6 nguồn)**
  SFR chuẩn hóa         Không        Không          Không            Có              **Có**
  RV32I compliance    Không rõ         Có             Có             Có          **37/38 PASS**
  RTL Language         Chisel      SpinalHDL       Verilog           SV         **SystemVerilog**

  : So sánh các dự án RISC-V SoC tiêu biểu
:::
:::

Từ bảng so sánh, có thể thấy thiết kế đề xuất có một số điểm khác biệt
đáng chú ý so với các giải pháp hiện có:

-   **Pipeline 7 tầng:** Hầu hết các thiết kế học thuật và nhúng chọn
    pipeline 2--5 tầng để đơn giản hóa xử lý hazard. Pipeline 7 tầng của
    thiết kế này tăng throughput tiềm năng và là thách thức lớn hơn về
    mặt xử lý RAW hazard, forwarding, và precise exception.

-   **Tích hợp đồng thời AXI-Lite và AHB-Lite:** Không có thiết kế nào
    trong danh sách khảo sát hỗ trợ cả hai giao thức AMBA trong cùng một
    SoC với CDC. Đây là tính năng đặc trưng của thiết kế này, phản ánh
    thực tế công nghiệp nơi các SoC phải kết nối với nhiều loại ngoại vi
    từ các nhà cung cấp khác nhau.

-   **CDC với Async FIFO:** Việc triển khai CDC bằng FIFO bất đồng bộ
    Gray code giữa hai miền xung nhịp là một giải pháp kỹ thuật phức
    tạp, phổ biến trong ASIC nhưng hiếm thấy trong các dự án học thuật
    cấp đại học cử nhân.

-   **SFR Standard Register Map:** Thiết kế một chuẩn thanh ghi thống
    nhất cho tất cả ngoại vi (lấy cảm hứng từ OpenTitan) giúp đảm bảo
    tính mở rộng của hệ thống mà không cần thay đổi RTL lõi.

## Khoảng Trống Nghiên Cứu

Qua khảo sát tài liệu, có thể xác định một số khoảng trống mà thiết kế
đề xuất nhằm lấp đầy trong phạm vi một khóa luận cử nhân:

Thứ nhất, đa số các thiết kế học thuật RISC-V tập trung vào một giao
thức bus duy nhất (hoặc giao thức bus riêng). Việc tích hợp đồng thời
AXI-Lite (1 GHz) và AHB-Lite (500 MHz) trong cùng một SoC với CDC an
toàn là một kịch bản kỹ thuật thực tế nhưng chưa được trình bày rõ ràng
ở cấp độ học thuật với đầy đủ kiểm chứng.

Thứ hai, kiểm chứng đa cấp độ -- từ unit test qua integration test đến
system test và compliance test chính thức -- thường không được trình bày
đầy đủ trong các công bố học thuật về thiết kế vi xử lý. Khóa luận này
đặt trọng tâm vào quy trình kiểm chứng có hệ thống như một đóng góp
phương pháp luận.

# CƠ SỞ LÝ THUYẾT {#Chapter3}

## Kiến Trúc Tập Lệnh RISC-V

### Tổng Quan RISC-V ISA

RISC-V là một kiến trúc tập lệnh mở (open ISA), được thiết kế theo triết
lý RISC (Reduced Instruction Set Computer): số lượng lệnh nhỏ, định dạng
cố định, và thực thi trong một chu kỳ trên pipeline lý tưởng
[@riscv-spec]. Điểm mạnh của RISC-V là tính module: một tập lệnh cơ sở
bắt buộc (RV32I hoặc RV64I) kết hợp với các phần mở rộng tùy chọn (M, A,
F, D, C, Zicsr, v.v.) cho phép thiết kế tùy chỉnh linh hoạt theo nhu cầu
ứng dụng.

Phần mở rộng **RV32I** (32-bit Integer Base) bao gồm 47 lệnh cơ bản, đủ
để chạy phần lớn phần mềm ứng dụng. RV32I định nghĩa:

-   32 thanh ghi nguyên x0--x31, mỗi thanh ghi 32 bit. Thanh ghi x0 luôn
    bằng 0 (hardwired zero).

-   Chiều rộng lệnh 32 bit cố định.

-   Không gian địa chỉ 32 bit, byte-addressable, word-aligned
    instruction fetch.

### Định Dạng Lệnh RV32I

RISC-V định nghĩa sáu định dạng mã hóa lệnh, tất cả đều 32 bit.
Hình [3.1](#fig:riscv-formats){reference-type="ref"
reference="fig:riscv-formats"} minh họa cấu trúc của từng định dạng.

<figure id="fig:riscv-formats">

<figcaption>Sáu định dạng mã hóa lệnh RV32I</figcaption>
</figure>

Bảng [3.1](#tab:instr-groups){reference-type="ref"
reference="tab:instr-groups"} tóm tắt các nhóm lệnh RV32I.

::: center
::: {#tab:instr-groups}
  **Nhóm**      **Lệnh tiêu biểu**                **Chức năng**
  ------------- --------------------------------- --------------------------------------
  Số học        ADD, SUB, ADDI                    Cộng/trừ thanh ghi và immediate
  Logic         AND, OR, XOR, ANDI, ORI, XORI     Phép logic bit
  Dịch bit      SLL, SRL, SRA, SLLI, SRLI, SRAI   Dịch trái/phải logic/số học
  So sánh       SLT, SLTU, SLTI, SLTIU            Ghi kết quả 0/1 vào rd
  Load          LW, LH, LB, LHU, LBU              Đọc từ bộ nhớ
  Store         SW, SH, SB                        Ghi vào bộ nhớ
  Nhánh         BEQ, BNE, BLT, BGE, BLTU, BGEU    Rẽ nhánh có điều kiện
  Nhảy          JAL, JALR                         Nhảy không điều kiện
  PC-relative   AUIPC                             Cộng imm dịch 12 bit vào PC
  Immediate     LUI                               Nạp 20-bit immediate vào rd\[31:12\]
  Hệ thống      ECALL, EBREAK                     Gọi hệ điều hành / gỡ lỗi

  : Các nhóm lệnh RV32I
:::
:::

### Phần Mở Rộng Zicsr

Phần mở rộng Zicsr thêm sáu lệnh đọc/ghi các thanh ghi điều khiển-trạng
thái (CSR -- Control and Status Register) và định nghĩa cơ chế xử lý
ngắt/ngoại lệ ở M-mode (Machine mode) [@riscv-priv-spec]. Khi xảy ra
trap (ngắt hoặc ngoại lệ), phần cứng tự động thực hiện chuỗi hành động:

1.  Lưu PC hiện tại vào `mepc`.

2.  Ghi nguyên nhân vào `mcause` (bit 31 phân biệt interrupt/exception).

3.  Lưu trạng thái ngắt `MIE` vào `MPIE` trong `mstatus`.

4.  Tắt ngắt toàn cục (`MIE` $\leftarrow$ 0).

5.  Chuyển PC đến vector trap (`mtvec + 4×cause` trong vectored mode).

Lệnh MRET phục hồi trạng thái trước trap: PC $\leftarrow$ `mepc`, `MIE`
$\leftarrow$ `MPIE`.

## Kiến Trúc Pipeline Processor

### Nguyên Lý Pipeline

Pipeline là kỹ thuật tổ chức CPU theo nhiều tầng (stage), mỗi tầng thực
hiện một phần của chu trình thực thi. Các tầng hoạt động song song, xử
lý các lệnh khác nhau cùng một lúc (instruction-level parallelism).
Throughput lý tưởng đạt 1 lệnh/chu kỳ (1 IPC).

<figure id="fig:pipeline-timing">

<figcaption>Nguyên lý hoạt động pipeline 7 tầng</figcaption>
</figure>

### Vấn Đề Hazard và Giải Pháp

Trong pipeline, **hazard** là điều kiện ngăn lệnh tiếp theo thực thi
ngay ở chu kỳ tiếp theo. Có ba loại hazard chính:

**1. Data hazard (RAW -- Read After Write):** Lệnh sau cần đọc dữ liệu
mà lệnh trước chưa ghi xong. Giải pháp chính là **data forwarding**
(bypass): dữ liệu được chuyển thẳng từ đầu ra tầng trước về đầu vào tầng
EX mà không cần chờ ghi vào register file. Trường hợp đặc biệt là
**load-use hazard**: lệnh LOAD có kết quả chỉ có ở tầng MEM2, nên lệnh
ngay sau không thể forward kịp từ EX -- cần stall 1 chu kỳ.

**2. Structural hazard:** Hai lệnh cùng cần sử dụng cùng một tài nguyên
phần cứng. Trong thiết kế pipeline với memory riêng biệt cho instruction
và data (Harvard architecture), structural hazard hầu như không xuất
hiện.

**3. Control hazard:** Branch/Jump -- khi CPU chưa biết địa chỉ đích, nó
đã nạp lệnh sai vào pipeline. Giải pháp đơn giản là **flush** (xóa) các
lệnh sai đã vào pipeline khi biết địa chỉ đích.

## Giao Thức AXI4-Lite

### Tổng Quan

AXI4-Lite (Advanced eXtensible Interface 4, Lite version) là giao thức
bus của ARM, thuộc tiêu chuẩn AMBA 4.0 [@amba-axi-spec]. AXI4-Lite được
thiết kế cho giao tiếp đơn giản với các thanh ghi điều khiển
(control/status registers) và là tiêu chuẩn phổ biến nhất trong hệ sinh
thái ARM và Xilinx/Intel FPGA.

### Cấu Trúc Kênh

AXI4-Lite sử dụng năm kênh giao tiếp độc lập:

::: center
::: {#tab:axi-channels}
  **Kênh**   **Hướng**                  **Tín hiệu chính**             **Mô tả**
  ---------- -------------------------- ------------------------------ ----------------
  AW         Master$\rightarrow$Slave   AWADDR, AWVALID, AWREADY       Write Address
  W          Master$\rightarrow$Slave   WDATA, WSTRB, WVALID, WREADY   Write Data
  B          Slave$\rightarrow$Master   BRESP, BVALID, BREADY          Write Response
  AR         Master$\rightarrow$Slave   ARADDR, ARVALID, ARREADY       Read Address
  R          Slave$\rightarrow$Master   RDATA, RRESP, RVALID, RREADY   Read Data

  : Năm kênh giao tiếp AXI4-Lite
:::
:::

### Giao Thức Handshake

Mỗi kênh AXI sử dụng cơ chế handshake VALID/READY: giao dịch xảy ra khi
cả VALID và READY đều bằng 1 tại cùng cạnh xung nhịp.
Hình [3.3](#fig:axi-waveform){reference-type="ref"
reference="fig:axi-waveform"} minh họa timing của một giao dịch ghi và
đọc AXI-Lite điển hình.

<figure id="fig:axi-waveform">

<figcaption>Dạng sóng giao dịch AXI4-Lite ghi và đọc</figcaption>
</figure>

## Giao Thức AHB-Lite

### Tổng Quan

AHB-Lite (Advanced High-performance Bus Lite) là phiên bản đơn master
của AHB trong tiêu chuẩn AMBA 3.0 [@amba-ahb-spec]. Khác với AXI,
AHB-Lite sử dụng một bus chia sẻ (shared bus) cho tất cả slave và cơ chế
pipelining giữa address phase và data phase.

### Hai Phase Giao Dịch

AHB-Lite phân chia một giao dịch thành hai phase kế tiếp nhau:

-   **Address Phase (Chu kỳ N):** Master phát địa chỉ (HADDR), loại giao
    dịch (HTRANS=NONSEQ), kích thước (HSIZE) và hướng (HWRITE) lên bus.

-   **Data Phase (Chu kỳ N+1):** Master phát dữ liệu ghi (HWDATA); slave
    phát dữ liệu đọc (HRDATA) và tín hiệu ready (HREADY). Slave có thể
    chèn wait state bằng cách giữ HREADY=0.

Điểm đặc biệt của AHB-Lite là address phase của giao dịch kế tiếp có thể
diễn ra đồng thời với data phase của giao dịch hiện tại, tạo ra
pipelining hiệu quả. Hình [3.4](#fig:ahb-waveform){reference-type="ref"
reference="fig:ahb-waveform"} minh họa timing AHB-Lite.

<figure id="fig:ahb-waveform">

<figcaption>Dạng sóng giao dịch AHB-Lite</figcaption>
</figure>

## Clock Domain Crossing

### Vấn Đề Metastability

Khi hai miền xung nhịp (clock domain) có tần số hoặc pha khác nhau cần
giao tiếp, tín hiệu từ miền nguồn có thể vi phạm yêu cầu setup/hold time
của flip-flop trong miền đích. Khi đó flip-flop có thể rơi vào trạng
thái **metastability** -- đầu ra không xác định, dao động trong khoảng
thời gian không biết trước. Nếu metastability truyền sang các logic tầng
sau, có thể gây lỗi hệ thống [@cummings-cdc].

### 2-FF Synchronizer

Giải pháp cơ bản nhất cho CDC một bit là sử dụng **2-FF synchronizer**:
tín hiệu bất đồng bộ đi qua hai flip-flop tuần tự, cả hai dùng xung nhịp
của miền đích. Xác suất metastability giảm theo hàm mũ qua mỗi tầng FF
bổ sung. Trong thiết kế này, 2-FF synchronizer được dùng cho tín hiệu
ngắt từ AHB domain (500 MHz) sang CPU domain (1 GHz).

### Asynchronous FIFO với Gray Code

Để truyền dữ liệu nhiều bit giữa hai miền xung nhịp, giải pháp an toàn
là sử dụng **asynchronous FIFO** với con trỏ Gray code [@cummings-cdc].
Gray code đảm bảo chỉ một bit thay đổi mỗi bước đếm, nên con trỏ có thể
được đồng bộ hóa an toàn qua 2-FF synchronizer mà không bị hiện tượng
tear (đọc sai do nhiều bit thay đổi cùng lúc).

Hình [3.5](#fig:async-fifo){reference-type="ref"
reference="fig:async-fifo"} minh họa kiến trúc và nguyên lý hoạt động
của asynchronous FIFO với Gray code pointer.

<figure id="fig:async-fifo">

<figcaption>Kiến trúc Asynchronous FIFO với Gray code
pointer</figcaption>
</figure>

## Bộ Điều Khiển Ngắt Ưu Tiên (PLIC)

[plic]{acronym-label="plic" acronym-form="singular+full"} là một tiêu
chuẩn kiến trúc ngắt của RISC-V cho phép quản lý tập trung nhiều nguồn
ngắt ngoại vi trước khi đưa vào CPU [@sifive-plic]. PLIC hỗ trợ:

-   Nhiều nguồn ngắt với mức ưu tiên khác nhau (priority per source).

-   Ngưỡng ngắt (threshold) cho phép CPU lọc các ngắt có ưu tiên thấp.

-   Cơ chế claim/complete: CPU đọc CLAIM register để nhận ID ngắt, sau
    đó ghi vào COMPLETE khi xử lý xong.

PLIC đóng vai trò arbitrator trung gian: nhiều ngoại vi có thể kích hoạt
ngắt đồng thời, nhưng PLIC chỉ chuyển ngắt có ưu tiên cao nhất (cao hơn
ngưỡng) đến CPU qua tín hiệu `meip_in`. Điều này giúp giảm tải cho CPU
và chuẩn hóa cách xử lý ngắt trong hệ thống đa ngoại vi.

# THIẾT KẾ VÀ TRIỂN KHAI HỆ THỐNG {#Chapter4}

## Kiến Trúc Tổng Thể SoC

### Sơ Đồ Khối Hệ Thống

Hệ thống SoC được thiết kế xoay quanh module tổng hợp `soc_top`, bao gồm
ba phân vùng chức năng chính: **CPU domain** (1 GHz), **AXI-Lite
subsystem** (1 GHz), và **AHB-Lite subsystem** (500 MHz với CDC). Module
`soc_top` không chứa bất kỳ logic datapath nào -- tất cả logic được đóng
gói trong các module con và `soc_top` chỉ kết dây (wire-up) giữa chúng.
Triết lý thiết kế này giúp mỗi khối có thể kiểm thử độc lập.

<figure id="fig:soc-top-block">

<figcaption>Sơ đồ khối tổng thể hệ thống SoC RISC-V</figcaption>
</figure>

### Bản Đồ Bộ Nhớ

CPU sử dụng không gian địa chỉ 32 bit (4 GB).
Bảng [4.1](#tab:memory-map){reference-type="ref"
reference="tab:memory-map"} mô tả các vùng địa chỉ được decode trong hệ
thống.

::: center
::: {#tab:memory-map}
  **Vùng**   **Địa chỉ bắt đầu**   **Địa chỉ kết thúc**   **Kích thước**   **Bus/Latency**
  ---------- --------------------- ---------------------- ---------------- -----------------------
  IMEM       `0x0000_0000`         `0x0000_FFFF`          64 KB            Direct / 1 cycle
  DMEM       `0x0001_0000`         `0x0001_FFFF`          64 KB            Direct / 1 cycle
  PLIC       `0x0C00_0000`         `0x0CFF_FFFF`          16 MB            Direct / 1 cycle
  AXI-Lite   `0x2000_0000`         `0x2FFF_FFFF`          256 MB           AXI / 4--6 cycle
  AHB-Lite   `0x3000_0000`         `0x3FFF_FFFF`          256 MB           AHB+CDC / 6--12 cycle

  : Bản đồ bộ nhớ hệ thống SoC
:::
:::

Trong phạm vi vùng AXI và AHB, các slave được phân biệt bằng các bit địa
chỉ `addr[27:12]` (slave ID) và `addr[11:0]` (offset trong slave). Việc
này cho phép mở rộng tối đa 65536 slave mỗi bus và 4 KB thanh ghi mỗi
slave.

### Miền Xung Nhịp

Hệ thống có hai miền xung nhịp:

-   **clk_cpu (1 GHz):** Toàn bộ CPU pipeline, IMEM, DMEM, PLIC, AXI
    interface, và Zicsr.

-   **clk_ahb (500 MHz):** AHB interface FSM, ahb_interconnect, và các
    AHB SFR slave.

Reset được thiết kế theo cơ chế **async assert, sync deassert**: khi mất
reset, tín hiệu lan truyền ngay lập tức đến tất cả flip-flop; khi cấp
lại reset, module `reset_sync` cần 2 chu kỳ `clk_ahb` để phục hồi an
toàn tín hiệu `rst_ahb_n` cho domain 500 MHz.

## Pipeline CPU 7 Tầng

Pipeline CPU được tổ chức thành 7 tầng như minh họa trong
Hình [4.2](#fig:pipeline-block){reference-type="ref"
reference="fig:pipeline-block"}. Giữa mỗi cặp tầng liên tiếp là một
thanh ghi pipeline lưu trữ tất cả tín hiệu dữ liệu và điều khiển cần cho
tầng kế tiếp.

<figure id="fig:pipeline-block">

<figcaption>Sơ đồ chi tiết pipeline CPU 7 tầng</figcaption>
</figure>

### Tầng IF1 -- Instruction Fetch Stage 1

Tầng IF1 quản lý Program Counter (PC). Mỗi chu kỳ không bị stall, PC
tăng thêm 4 (word-aligned fetch). Khi xảy ra branch taken hoặc
trap/MRET, PC nhận địa chỉ mới từ `addr_adder` (EX stage) hoặc từ
`zicsr_pc`. Ưu tiên: Zicsr \> EX. PC được gửi trực tiếp đến IMEM trong
cùng chu kỳ.

### Tầng IF2 -- Instruction Fetch Stage 2

IMEM có latency 1 chu kỳ, nên kết quả đọc instruction xuất hiện ở tầng
IF2. Tầng IF2 hội tụ (merge) giữa instruction từ IMEM và PC từ thanh ghi
IF1/IF2, tạo ra cặp (PC, instr) chuyển sang ID. Module `imem` hỗ trợ tín
hiệu `stall` (giữ output) và `flush` (xuất NOP -- `addi x0,x0,0`) để
đồng bộ với pipeline.

### Tầng ID -- Instruction Decode

Tầng ID bao gồm hai module: `id_decoder` giải mã lệnh 32 bit thành tất
cả tín hiệu điều khiển cần thiết, và `register_file` đọc hai thanh ghi
nguồn rs1/rs2. Module `id_decoder` xác định loại lệnh, địa chỉ thanh
ghi, immediate value, và các tín hiệu điều khiển cho các tầng sau.

Một điểm thiết kế quan trọng là **WBR bypass** trong `register_file`:
đọc thanh ghi kết hợp kiểm tra xem WB stage có đang ghi vào cùng địa chỉ
không. Nếu có (và rd $\neq$ x0), dữ liệu từ WB được trả về trực tiếp
thay vì đọc từ mảng thanh ghi. Điều này xử lý gap-4 RAW hazard mà không
cần stall.

### Tầng EX -- Execute

Tầng EX được đóng gói trong module `ex_stage`, bao gồm:

-   **ALU:** Thực hiện 11 phép tính (ADD, SUB, AND, OR, XOR, SLL, SRL,
    SRA, SLT, SLTU, PASSB cho LUI).

-   **Branch Comparator:** Đánh giá điều kiện branch (BEQ, BNE, BLT,
    BGE, BLTU, BGEU).

-   **Address Adder:** Tính địa chỉ đích branch/jump (PC-relative hoặc
    register-relative cho JALR); JALR mask bit 0 theo đặc tả ISA.

-   **Forwarding Unit và MUX:** Chọn giữa dữ liệu từ register file và
    forwarding từ MEM1/MEM2/WB.

`ex_stage` xuất `branch_taken` và `addr_out` về hazard unit để quyết
định flush pipeline khi branch taken hoặc jump.

### Tầng MEM1 -- Memory Access Stage 1

Tầng MEM1 là điểm phân nhánh của địa chỉ: module `mem1_stage` decode địa
chỉ từ ALU result và phát tín hiệu điều khiển đến đúng subsystem:

-   `addr[31:16] == 16’h0001`: Truy cập DMEM -- không stall.

-   `addr[31:24] == 8’h0C`: Truy cập PLIC -- không stall, latency 1 chu
    kỳ.

-   `addr[31:28] == 4’h2`: Truy cập AXI-Lite -- phát
    `bus_stall_req = 1`.

-   `addr[31:28] == 4’h3`: Truy cập AHB-Lite -- phát
    `bus_stall_req = 1`.

-   Không khớp: Phát `load_fault`/`store_fault` để Zicsr sinh ngoại lệ.

Khi `bus_stall_req = 1`, toàn bộ pipeline từ IF1 đến MEM1 bị đóng băng
(stall) cho đến khi bus transaction hoàn thành.

### Tầng MEM2 -- Memory Access Stage 2

Tầng MEM2 thu kết quả từ DMEM (1 chu kỳ latency), AXI interface, hoặc
AHB (qua Response FIFO). Tín hiệu `mem_src[1:0]` chọn nguồn dữ liệu:
DMEM, AXI, hoặc AHB. Tầng này cũng xử lý sign/zero extension cho các
lệnh load byte và halfword (LB, LBU, LH, LHU) dựa trên `mem_size` và
`mem_ext`.

### Tầng WB -- Write Back

Tầng WB chọn dữ liệu kết quả cuối cùng và ghi vào register file. Tín
hiệu `wb_sel[1:0]` chọn từ bốn nguồn: kết quả ALU (00), dữ liệu load từ
MEM2 (01), PC+4 cho JAL/JALR link (10), và dữ liệu CSR đọc (11).

## Xử Lý Hazard và Forwarding

### Forwarding Unit

Module `forwarding_unit` phát hiện và giải quyết RAW hazard theo ưu tiên
từ cao đến thấp: MEM1 (gap-1) $>$ MEM2 (gap-2) $>$ WB (gap-3). Kết quả
là tín hiệu `fwd_sel_a[1:0]` và `fwd_sel_b[1:0]` chọn nguồn dữ liệu cho
hai đầu vào của ALU. Nhờ forwarding, các lệnh RAW ở gap-1, gap-2, và
gap-3 không cần stall.

### Hazard Unit

Module `hazard_unit` tổng hợp tất cả các tín hiệu stall và flush cho
pipeline. Bảng [4.2](#tab:hazard){reference-type="ref"
reference="tab:hazard"} tóm tắt các loại hazard và cách xử lý.

::: center
::: {#tab:hazard}
  **Loại Hazard**       **Cơ chế xử lý**                     **Số chu kỳ stall**
  --------------------- ---------------------------------- ------------------------
  Gap-1, 2, 3 RAW       Forwarding từ MEM1/MEM2/WB                    0
  Gap-4 RAW             WBR bypass trong register_file                0
  Load-use              Stall IF1..ID, bubble vào EX                  1
  CSR-use (EX)          Stall IF1..ID                                 3
  CSR-use (MEM1)        Stall IF1..ID                                 2
  CSR-use (MEM2)        Stall IF1..ID                                 1
  Branch/Jump           Flush IF1/IF2 và IF2/ID             2 (flush, không stall)
  Bus stall (AXI/AHB)   Stall toàn pipeline IF1..MEM1          N (đến khi xong)
  Trap/MRET (Zicsr)     Flush toàn pipeline, load PC mới              --

  : Tổng hợp các loại hazard và cơ chế xử lý trong pipeline 7 tầng
:::
:::

Một vấn đề thiết kế tinh tế là **bus stall kết hợp load-use hazard**:
khi có lệnh SW ở MEM1 (đang bus stall), LW ở EX (có load-use với lệnh
tiếp theo), và lệnh đọc ở ID -- ba điều kiện này có thể xảy ra đồng
thời. Giải pháp đúng là khi `bus_stall_req = 1`, không được phát
`flush_id_ex` cho load-use (vì toàn pipeline đã bị đóng băng, bubble sẽ
được tạo tự nhiên sau khi bus giải phóng).

## Hệ Thống Bộ Nhớ

IMEM và DMEM đều là bộ nhớ synchronous 1 chu kỳ latency, mỗi loại 64 KB.
Hệ thống sử dụng kiến trúc Harvard -- IMEM chỉ được đọc qua PC
(instruction fetch path) và DMEM được truy cập qua ALU result (data
path). Hai bộ nhớ này là hai mảng vật lý độc lập, nên không có
structural hazard.

IMEM được tham số hóa với `SIZE_KB` (mặc định 64 KB) để cho phép
compliance testbench override lên 512 KB khi chạy bộ kiểm thử RV32I (một
số bài kiểm thử branch có code size lên đến 293 KB).

## Giao Diện Bus AXI-Lite

### AXI Interface FSM

Module `axi_interface` là FSM (Finite State Machine) chuyển đổi từ giao
thức nội bộ CPU (req_valid/resp_valid) sang AXI4-Lite 5 kênh. Đối với
giao dịch **ghi**, FSM trải qua ba trạng thái: AW_W_PHASE (phát AWVALID
và WVALID đồng thời), B_PHASE (nhận BRESP), và trở về IDLE khi
`axi_resp_valid = 1`. Đối với giao dịch **đọc**: AR_PHASE (phát
ARVALID), R_PHASE (nhận RDATA), và trở về IDLE. Tín hiệu
`axi_resp_valid = 1` báo hiệu `mem1_stage` giải phóng `bus_stall_req`.

Hình [4.3](#fig:axi-fsm){reference-type="ref" reference="fig:axi-fsm"}
minh họa sơ đồ trạng thái của AXI Interface FSM.

<figure id="fig:axi-fsm">

<figcaption>Sơ đồ trạng thái AXI Interface FSM</figcaption>
</figure>

### AXI Interconnect và SFR Slave

Module `axi_interconnect` decode địa chỉ `addr[27:12]` để chọn một trong
ba slave (S0, S1, S2). Mỗi slave là một `axi_sfr` -- triển khai SFR
Standard Register Map 9 thanh ghi (xem
Mục [4.9](#sec:sfr-map){reference-type="ref" reference="sec:sfr-map"}).
Trong trường hợp địa chỉ không decode được, interconnect trả về DECERR
(BRESP/RRESP = 2'b11), kích hoạt bus error exception.

## Giao Diện Bus AHB-Lite và CDC

### Asynchronous FIFO (CDC)

Ranh giới giữa miền CPU (1 GHz) và miền AHB (500 MHz) được xử lý bởi hai
FIFO bất đồng bộ:

-   **Request FIFO (1 GHz $\rightarrow$ 500 MHz):** Rộng 67 bit =
    Address(32) + WriteData(32) + Control(3: write/size). Được ghi bởi
    `mem1_stage` và đọc bởi `ahb_interface`.

-   **Response FIFO (500 MHz $\rightarrow$ 1 GHz):** Rộng 33 bit =
    HRDATA(32) + HRESP(1). Được ghi bởi `ahb_interface` và đọc bởi
    `mem1_stage`.

Cả hai FIFO có độ sâu 2 (lũy thừa của 2, yêu cầu tối thiểu cho Gray
code). Vì CPU bị stall cứng trong suốt bus transaction, không có
overflow -- chỉ cần flag `empty` để kiểm tra trạng thái. Không dùng flag
`full`.

### AHB Interface FSM

Module `ahb_interface` chạy ở 500 MHz, đọc request từ Request FIFO và
thực thi giao dịch AHB-Lite. FSM có ba trạng thái: IDLE (chờ request),
ADDR (phát HADDR và HTRANS=NONSEQ), và DATA (phát HWDATA hoặc đọc HRDATA
khi HREADY=1). Khi giao dịch hoàn thành, kết quả được ghi vào Response
FIFO.

### Đồng Bộ IRQ AHB

Tín hiệu ngắt từ các AHB slave (500 MHz) cần được đồng bộ hóa trước khi
vào PLIC (1 GHz). Module `irq_sync2ff` (2-FF synchronizer, 1 GHz) thực
hiện việc này -- có một instance cho mỗi AHB slave (tổng cộng ba
instance trong `soc_top`). IRQ từ AXI slave (1 GHz) được kết nối thẳng
vào PLIC.

## Bộ Điều Khiển Ngắt Ưu Tiên (PLIC)

Module `plic` triển khai PLIC theo đặc tả SiFive với 6 nguồn ngắt (3 từ
AXI slave + 3 từ AHB slave sau khi đồng bộ). Các tính năng chính:

-   **Priority per source:** Mỗi nguồn có thanh ghi ưu tiên 3 bit (0 =
    vô hiệu hóa, 1-7 = mức ưu tiên).

-   **Threshold:** CPU có thể ghi ngưỡng ưu tiên; chỉ ngắt có ưu tiên
    cao hơn ngưỡng mới được chuyển lên.

-   **Claim/Complete:** CPU đọc register CLAIM để nhận ID của ngắt đang
    chờ (ngắt có ưu tiên cao nhất, cao hơn ngưỡng); ghi vào COMPLETE sau
    khi xử lý xong.

-   **Latency 1 chu kỳ:** PLIC được ánh xạ vào địa chỉ `0x0C000000`,
    phản hồi trong 1 chu kỳ, không gây stall.

PLIC xuất tín hiệu `meip_in` đến module Zicsr để kích hoạt Machine
External Interrupt.

## Khối CSR và Xử Lý Ngắt/Ngoại Lệ (Zicsr)

Module `zicsr` quản lý sáu thanh ghi CSR và xử lý toàn bộ trap (ngắt +
ngoại lệ) tại M-mode. Zicsr nhận tín hiệu từ tầng WB của pipeline (vì
ngắt và ngoại lệ được xử lý khi lệnh gây ra nó đến WB -- đây là điều
kiện **precise exception**).

### Các Nguồn Trap

-   **Exception:** ECALL, EBREAK, Illegal Instruction, Load/Store Access
    Fault -- khi lệnh đến WB.

-   **Interrupt:** Machine External Interrupt (từ PLIC), Machine
    Software Interrupt (từ phần mềm) -- được kiểm tra mỗi chu kỳ khi
    `mstatus.MIE = 1`.

-   **Bus Error:** BRESP/RRESP SLVERR (AXI) hoặc HRESP ERROR (AHB) --
    được phát hiện và chuyển thành Load/Store Fault.

### Precise Exception

Khi có bus transaction đang diễn ra (`bus_stall_req = 1`), Zicsr
**không** được flush pipeline. Điều này đảm bảo bus transaction không bị
hủy ngang chừng -- **precise exception** đòi hỏi phải chờ giao dịch bus
hoàn thành trước khi xử lý trap.

### Vectored Interrupt Mode

Với `mtvec[1:0] = 01` (vectored mode), địa chỉ vector trap được tính là:
$$\text{PC}_{\text{trap}} = (\texttt{mtvec} \, \& \, \sim3) + 4 \times \texttt{cause\_code}$$
Mỗi nguyên nhân trap có vector riêng biệt, giúp giảm độ trễ xử lý ngắt
bằng cách tránh switch-case trong phần mềm.

## SFR Standard Register Map {#sec:sfr-map}

Mọi ngoại vi kết nối vào hệ thống phải triển khai SFR Standard Register
Map (lấy cảm hứng từ OpenTitan), đảm bảo tính nhất quán và khả năng
plug-and-play. Bảng [4.3](#tab:sfr-map){reference-type="ref"
reference="tab:sfr-map"} mô tả cấu trúc thanh ghi chuẩn.

::: center
::: {#tab:sfr-map}
   **Offset**  **Tên**       **Access**   **Mô tả**
  ------------ ------------- ------------ -------------------------------------------------------
     `0x00`    CTRL          RW           `bit[0]` = enable; bits\[31:1\] = peripheral-specific
     `0x04`    STATUS        RO           Trạng thái read-only do peripheral drive
     `0x08`    INTR_ENABLE   RW           Mask từng nguồn IRQ
     `0x0C`    INTR_STATE    RW1C         Pending flags -- ghi 1 để clear
     `0x10`    INTR_TEST     WO           Ghi 1 để force-set INTR_STATE (debug)
     `0x14`    DATA0         RW           General-purpose (peripheral-specific)
     `0x18`    DATA1         RW           General-purpose
     `0x1C`    DATA2         RW           General-purpose
     `0xFC`    PERIPH_ID     RO           Hardcoded peripheral identifier

  : SFR Standard Register Map -- bố cục thanh ghi chuẩn cho mọi ngoại vi
:::
:::

Quy tắc IRQ: `irq = |(INTR_STATE & INTR_ENABLE)` -- ngắt chỉ được phát
khi có event đang pending VÀ được enable. Thanh ghi INTR_TEST cho phép
phần mềm kiểm tra đường ngắt mà không cần kích hoạt sự kiện thực sự.

Trong khóa luận này, hai loại SFR được triển khai: `axi_sfr` cho bus
AXI-Lite và `ahb_sfr` cho bus AHB-Lite. Ngoài ra, `gpio_sfr` là một ví
dụ ngoại vi hoàn chỉnh: `DATA0` điều khiển GPIO output, `STATUS` phản
ánh GPIO input, và edge-detect circuit tạo IRQ khi có cạnh tín hiệu.

## Kiến Trúc Chip Boundary

Module `soc_top` được thiết kế như một **chip boundary**: tất cả các
slave AXI và AHB được expose ra ngoài thông qua port declarations, cho
phép kết nối với ngoại vi bên ngoài mà không cần sửa đổi RTL bên trong
chip. `soc_top` xuất:

-   `rst_cpu_n_o`, `rst_ahb_n_o`: Reset đã đồng bộ, để ngoại vi dùng
    reset flip-flop của mình.

-   `axi_S{0,1,2}_*`: Đầy đủ cổng AXI-Lite slave cho ba slave.

-   `ahb_S{0,1,2}_*`: Cổng AHB-Lite cho ba slave.

Triết lý này đảm bảo bất kỳ ngoại vi nào tuân thủ SFR Standard đều có
thể được gắn vào mà không cần thay đổi RTL trong chip.

# KẾT QUẢ THỰC NGHIỆM {#Chapter5}

## Môi Trường Kiểm Thử

### Công Cụ và Thiết Lập

Toàn bộ quá trình kiểm thử được thực hiện trên hệ thống Linux với các
công cụ sau:

-   **Icarus Verilog 12** (`iverilog -g2012 -Wall`): Biên dịch và mô
    phỏng RTL SystemVerilog.

-   **riscv64-unknown-elf-gcc 13.2.0**: Biên dịch chương trình thử
    nghiệm RISC-V.

-   **GTKWave**: Xem và phân tích dạng sóng VCD.

-   **GNU Make**: Tự động hóa toàn bộ quy trình build và test.

-   **riscv-arch-test (old-framework-2.x)**: Bộ kiểm thử tuân thủ RV32I
    chính thức.

Mọi testbench đều sử dụng **tự kiểm tra tự động** (self-checking): tín
hiệu `PASS`/`FAIL` được in ra sau mỗi test case mà không cần so sánh thủ
công.

### Chiến Lược Kiểm Thử

Chiến lược kiểm thử được tổ chức thành các pha tăng dần về độ phức tạp:

<figure id="fig:test-pyramid">

<figcaption>Chiến lược kiểm thử phân cấp</figcaption>
</figure>

## Kiểm Thử Đơn Vị (Phase 1 và 2)

### Phase 1 -- Kiểm Thử Module Tổ Hợp

Phase 1 kiểm thử bốn module logic tổ hợp và đồng bộ quan trọng nhất của
pipeline. Tổng cộng 192 test case, tất cả PASS.

#### ALU -- 38 Test Case

Module ALU (`alu.sv`) thực hiện 11 phép tính với các giá trị biên đặc
trưng. Bảng [5.1](#tab:alu-tests){reference-type="ref"
reference="tab:alu-tests"} tóm tắt kết quả.

::: center
::: {#tab:alu-tests}
  **Nhóm phép tính**    **Số test**  **Corner case tiêu biểu**
  -------------------- ------------- ----------------------------------------------
  ADD                        4       Overflow wrap: `0xFFFF_FFFF + 1 = 0`
  SUB                        3       Underflow: `0 - 1 = 0xFFFF_FFFF`
  SLL/SRL/SRA               10       Shift 0, shift 31, shift 32 (modulo 32)
  SLT/SLTU                   5       So sánh số âm và số dương, zero
  AND/OR/XOR                 8       All zeros, all ones, alternating bits
  PASSB (LUI)                4       Chuyển nguyên immediate, kiểm tra upper bits
  **Tổng**                           **38/38 PASS**

  : Kết quả kiểm thử ALU -- 38 test case
:::
:::

#### Branch Comparator -- 30 Test Case

Module `branch_comp` kiểm thử sáu điều kiện branch: BEQ, BNE, BLT, BGE,
BLTU, BGEU. Đặc biệt chú ý đến trường hợp biên: số âm lớn nhất, số dương
lớn nhất, và so sánh có/không có dấu (BLT vs BLTU cho giá trị
0x80000000).

#### Register File -- 36 Test Case

Kiểm thử `register_file` tập trung vào hai tính năng đặc biệt: (1) x0
hardwired zero (không thể ghi), (2) WBR bypass (gap-4 RAW hazard) -- đọc
và ghi cùng địa chỉ trong cùng chu kỳ phải trả về dữ liệu mới.

#### Instruction Decoder -- 88 Test Case

Module `id_decoder` được kiểm thử với tất cả loại lệnh RV32I và Zicsr.
Kiểm tra đặc biệt: immediate sign-extension cho từng định dạng lệnh, xác
định đúng `alu_op` cho từng lệnh.

### Phase 2 -- Kiểm Thử Module Đồng Bộ

Phase 2 bổ sung ba module có trạng thái (stateful): `forwarding_unit`,
`hazard_unit`, và `async_fifo`. Tổng cộng 114 test case, tất cả PASS.

#### Forwarding Unit -- 31 Test Case

Kiểm thử tất cả tổ hợp forwarding cho rs1 và rs2: không forward (00), từ
MEM1 (01), từ MEM2 (10), từ WB (11). Đặc biệt kiểm tra trường hợp rd =
x0 (không được forward), và conflict giữa forwarding từ MEM1 và MEM2
(MEM1 phải thắng).

#### Hazard Unit -- 73 Test Case

Module `hazard_unit` là module phức tạp nhất trong pipeline. Các test
case bao gồm:

-   Load-use hazard đơn giản (1 stall cycle).

-   CSR-use hazard ở gap 1, 2, 3 (3/2/1 stall cycle tương ứng).

-   Branch/Jump flush (2 slot flush).

-   Bus stall kết hợp load-use -- tình huống đặc biệt quan trọng.

-   Zicsr flush toàn pipeline.

#### Async FIFO -- 10 Test Case

Module `async_fifo` (depth=2) được kiểm thử với các trường hợp: ghi và
đọc bình thường, kiểm tra flag empty chính xác, ghi khi FIFO trống, đọc
khi FIFO có 1 phần tử, và kiểm tra Gray code pointer ở biên
(wrap-around).

## Kiểm Thử Tích Hợp Pipeline (Phase 3)

Phase 3 là lần đầu tiên toàn bộ pipeline CPU được chạy với chương trình
thực sự thông qua `soc_top`. Chín chương trình thử nghiệm kiểm tra từng
nhóm lệnh, từng loại hazard và các tình huống đặc biệt. Kết quả: **9/9
PASS**.

::: center
::: {#tab:phase3-programs}
  **Chương trình**   **Nội dung kiểm thử**
  ------------------ -------------------------------------------------------------
  prog_arithmetic    Tất cả lệnh số học: ADD/SUB/AND/OR/XOR/SLT/LUI/AUIPC
  prog_shift         SLL/SRL/SRA với shift amount biên (0, 1, 31)
  prog_forwarding    RAW hazard gap-1, 2, 3, 4 với nhiều chuỗi lệnh phụ thuộc
  prog_load_store    LW/LH/LB/LHU/LBU/SW/SH/SB -- địa chỉ và dữ liệu biên
  prog_branch_jump   BEQ/BNE/BLT/BGE/BLTU/BGEU taken và not-taken; JAL/JALR
  prog_load_use      Load-use hazard: LW theo sau ngay bởi lệnh dùng kết quả
  prog_ecall         ECALL, EBREAK, Illegal Instruction → trap handler → MRET
  prog_csr           CSRRW/CSRRS/CSRRC/CSRxI -- đọc/ghi/modify mstatus/mie/mtvec
  prog_interrupt     Software interrupt (MSI) -- kích hoạt, xử lý handler, clear

  : Chương trình kiểm thử pipeline (Phase 3) -- 9/9 PASS
:::
:::

Trong quá trình kiểm thử Phase 3, hai bug quan trọng trong RTL được phát
hiện và sửa:

1.  **Bug B3 -- Gap-4 RAW hazard:** `register_file` không có WBR bypass
    cho trường hợp WB ghi và ID đọc cùng địa chỉ trong cùng chu kỳ. Sửa
    bằng cách thêm combinational bypass.

2.  **Bug B6 -- Ghost instruction:** Sau `zicsr_flush`, IMEM tiếp tục
    xuất instruction của địa chỉ cũ trong chu kỳ tiếp theo, gây illegal
    instruction spurious. Sửa bằng cách thêm tín hiệu flush vào IMEM để
    xuất NOP.

## Kiểm Thử Giao Diện Bus (Phase 4)

Phase 4 được chia thành bốn sub-phase, tăng dần từ kiểm thử interface
đơn lẻ đến full path với interconnect và SFR slave. Tổng cộng 163 test
case, tất cả PASS.

### Phase 4a -- AXI Interface (49 Test Case)

`tb_axi_interface` sử dụng slave model AXI giả để kiểm thử module
`axi_interface`. Các test case bao gồm:

-   Giao dịch ghi: one-shot, wait state (slave AWREADY delay), BRESP
    SLVERR (bus error).

-   Giao dịch đọc: one-shot, ARREADY delay, RVALID delay, RRESP SLVERR.

-   Kiểm tra bus stall: pipeline giữ nguyên trong suốt giao dịch.

-   Kiểm tra `axi_resp_valid` timing: bus stall giải phóng đúng thời
    điểm.

### Phase 4b -- AHB Interface và CDC (29 Test Case)

`tb_ahb_interface` kiểm thử `ahb_interface` kết hợp với hai FIFO bất
đồng bộ. Đây là kiểm thử CDC đầu tiên -- các giao dịch được phát từ
domain 1 GHz và nhận ở domain 500 MHz, sau đó kết quả đi ngược về 1 GHz.
Test case đặc biệt: HRESP ERROR (AHB bus error) → phát hiện và báo lên
CPU.

Hình [5.2](#fig:cdc-waveform){reference-type="ref"
reference="fig:cdc-waveform"} minh họa waveform của một giao dịch hoàn
chỉnh qua CDC.

<figure id="fig:cdc-waveform">

<figcaption>Dạng sóng giao dịch CDC – Request FIFO và Response
FIFO</figcaption>
</figure>

### Phase 4c -- AXI Full Path (47 Test Case)

`tb_axi_full` kiểm thử chuỗi đầy đủ: `axi_interface` +
`axi_interconnect` + 3 `axi_sfr`. Các test case bao gồm:

-   Ghi/đọc đến từng slave S0, S1, S2.

-   Kiểm tra decode địa chỉ đúng: ghi vào S0 không ảnh hưởng S1, S2.

-   Kiểm tra toàn bộ 9 thanh ghi SFR Standard per slave.

-   Kiểm tra INTR_STATE/INTR_ENABLE và logic IRQ.

-   Kiểm tra INTR_TEST: force-set INTR_STATE để kiểm tra đường IRQ.

### Phase 4d -- AHB Full Path (38 Test Case)

`tb_ahb_full` là tương đương của Phase 4c cho bus AHB: `ahb_interface` +
CDC FIFO + `ahb_interconnect` + 3 `ahb_sfr`. Kiểm tra wait state
(HREADYOUT = 0 từ slave), HRESP ERROR propagation, và SFR Standard
Register Map qua AHB protocol.

## Kiểm Thử Hệ Thống (Phase 5 và 6)

### Phase 5 -- Tích Hợp SoC + AXI/AHB (4 Chương Trình)

Phase 5 là lần đầu tiên CPU thực sự truy cập ngoại vi qua bus thông qua
`soc_top`. Bốn chương trình kiểm thử:

1.  **prog_axi_sfr**: CPU ghi/đọc các thanh ghi AXI SFR; kiểm tra kết
    quả đúng.

2.  **prog_ahb_sfr**: CPU ghi/đọc các thanh ghi AHB SFR qua CDC; kiểm
    tra kết quả đúng.

3.  **prog_axi_irq**: CPU cấu hình AXI SFR IRQ, kích hoạt ngắt qua
    INTR_TEST, xử lý ISR, clear INTR_STATE.

4.  **prog_ahb_irq**: Tương tự với AHB SFR -- IRQ từ 500 MHz domain, qua
    2-FF sync, đến PLIC, đến CPU.

Kết quả: **4/4 PASS**. Trong quá trình này, bug B8 được phát hiện: bus
stall kết hợp load-use hazard gây LW bị hủy oan. Sửa trong
`hazard_unit.sv`.

### Phase 6a -- System Batch Test (20 Chương Trình)

`tb_soc_top` chạy tự động 20 chương trình qua `soc_top` với sequence
reset chuẩn, bao gồm tất cả 9 chương trình từ Phase 3 cộng thêm 11
chương trình mới kiểm tra các tình huống phức tạp hơn.

<figure id="fig:pipeline-waveform">

<figcaption>Dạng sóng pipeline CPU trong quá trình mô phỏng hệ
thống</figcaption>
</figure>

Kết quả: **20/20 PASS**.

### Phase 6b -- Compliance Framework (3 Chương Trình)

`tb_compliance` sử dụng framework riêng tương tự riscv-arch-test để kiểm
tra các trường hợp đặc biệt: shifts (tất cả shift operations với biên),
compare (SLT/SLTU với signed/unsigned edge cases), và dmem_endurance
(ghi/đọc 256 địa chỉ DMEM liên tiếp). Kết quả: **3/3 TEST_PASS**.

## Kiểm Thử PLIC và EX Stage (Phase 7 và 8)

### Phase 7 -- PLIC Unit Test (31 Test Case) và Hệ Thống (3 Chương Trình)

`tb_plic` kiểm thử module `plic` với 31 test case bao gồm:

-   Không có ngắt -- PLIC xuất meip=0.

-   Ngắt đơn nguồn với priority \> 0.

-   Nhiều ngắt đồng thời -- PLIC chọn nguồn có priority cao nhất.

-   Threshold: ngắt có priority = threshold không được chuyển lên CPU.

-   Claim/Complete cycle: CLAIM trả về ID đúng, COMPLETE clear pending.

-   Edge case: priority = 0 (disabled), priority wrap-around.

Ba chương trình hệ thống (`prog_plic_basic`, `prog_plic_priority`,
`prog_plic_threshold`) kiểm tra PLIC trong môi trường SoC hoàn chỉnh.
Kết quả: **31/31 PASS + 3/3 PASS**.

### Phase 8 -- EX Stage Unit Test (23 Test Case) và CSR Hazard

`tb_ex_stage` kiểm thử module `ex_stage` như một đơn vị hoàn chỉnh (bao
gồm forwarding_unit, ALU, branch_comp, addr_adder và các MUX bên trong).
Đặc biệt kiểm tra:

-   Forwarding override: khi có forwarding, ALU sử dụng dữ liệu mới
    nhất.

-   Branch resolution: branch_taken đúng với tất cả sáu điều kiện.

-   JALR address masking: bit 0 của địa chỉ đích được mask.

Chương trình `prog_csr_hazard` chạy qua tất cả CSR-use gap (0--4): lệnh
CSR ở EX/MEM1/MEM2/WB và lệnh tiếp theo đọc kết quả CSR với các khoảng
cách khác nhau. Hazard unit phải stall đúng số chu kỳ. Kết quả: **23/23
PASS + 1/1 PASS**.

## Kiểm Thử Đơn Vị Bổ Sung

Ba module phụ được bổ sung unit test riêng trong giai đoạn hoàn thiện:

::: center
::: {#tab:new-unit-tests}
  **Testbench**     **Kết quả**  **Nội dung chính**
  ---------------- ------------- ------------------------------------------------------
  tb_irq_sync2ff    10/10 PASS   2-FF sync: glitch rejection, latency 2 cycle
  tb_gpio_sfr       22/22 PASS   GPIO output (DATA0), input (STATUS), edge-detect IRQ
  tb_zicsr          38/38 PASS   CSRRW/RS/RC, trap handler, MRET, bus error exception

  : Kết quả kiểm thử đơn vị bổ sung
:::
:::

## Kiểm Thử Bus Error

Hai testbench tích hợp kiểm tra trường hợp bus trả lỗi:

-   **tb_soc_bus_err:** AXI slave trả BRESP=SLVERR (store) → `mcause=7`
    (Store Fault); RRESP=SLVERR (load) → `mcause=5` (Load Fault). Kết
    quả: **2/2 PASS**.

-   **tb_soc_ahb_err:** AHB slave trả HRESP=ERROR → load/store fault
    tương ứng. Kết quả: **2/2 PASS**.

Hình [5.4](#fig:bus-error-waveform){reference-type="ref"
reference="fig:bus-error-waveform"} minh họa quá trình phát hiện và xử
lý bus error.

<figure id="fig:bus-error-waveform">

<figcaption>Dạng sóng xử lý bus error (BRESP SLVERR <span
class="math inline">→</span> Store Fault)</figcaption>
</figure>

## Kiểm Thử Tuân Thủ RV32I

### Bộ Kiểm Thử riscv-arch-test

Bộ kiểm thử tuân thủ chính thức `riscv-arch-test` (old-framework-2.x)
của tổ chức RISC-V International [@riscv-arch-test] kiểm tra tất cả lệnh
cơ bản của RV32I bằng phương pháp signature-based:

1.  Mỗi test program thực thi một chuỗi lệnh và ghi kết quả vào vùng nhớ
    "signature" trong DMEM.

2.  Sau khi mô phỏng, testbench dump signature ra file.

3.  Script so sánh signature với file tham chiếu được tạo từ ISS chuẩn
    (Spike).

4.  Nếu signature khớp hoàn toàn: PASS; ngược lại: FAIL.

### Thiết Lập Đặc Biệt

Một số điều chỉnh kỹ thuật cần thiết để chạy bộ kiểm thử này:

**1. IMEM 512 KB cho branch tests:** Các test BEQ/BNE/BLT/BGE/BLTU/BGEU
sử dụng test vector rất dày đặc, sinh code size lên đến 293 KB -- vượt
quá IMEM 64 KB của phần cứng. Giải pháp: tham số hóa IMEM
(`IMEM_SIZE_KB`) và override lên 512 KB trong compliance testbench. Đây
là kiến trúc Harvard nên IMEM và DMEM là hai mảng độc lập -- không có
xung đột địa chỉ.

**2. DMEM preload cho load tests:** Các test LB/LBU/LH/LHU/LW đọc dữ
liệu từ vùng `rvtest_data` được khai báo trong section `.data`.
Testbench cần đọc section này từ file ELF và nạp vào DMEM trước khi chạy
mô phỏng.

**3. X-bit handling:** Icarus Verilog khởi tạo mảng DMEM với giá trị X
(không xác định). Các từ trong signature chưa được ghi phải xuất ra
`"00000000"` (Spike khởi tạo bộ nhớ bằng 0). Kiểm tra `^word === 1’bx`
để phân biệt từ chứa X.

**4. Patch jalr-01.S:** Một test case trong `jalr-01.S` dùng macro mở
rộng thành lệnh `la x0, label` -- bị binutils
$\geq$`<!-- -->`{=html}2.39 từ chối vì x0 là zero register. Patch thay
bằng code tương đương dùng register hợp lệ, cho cùng kết quả signature.

### Kết Quả Tuân Thủ

Bảng [5.4](#tab:compliance-results){reference-type="ref"
reference="tab:compliance-results"} trình bày kết quả chi tiết của bộ
kiểm thử RV32I.

::: center
::: {#tab:compliance-results}
  **Nhóm lệnh**    **Kết quả**  **Ghi chú**
  --------------- ------------- --------------------------------------------------------------------------
  addi-01             PASS      
  add-01              PASS      
  andi-01             PASS      
  and-01              PASS      
  auipc-01            PASS      
  beq-01              PASS      512 KB IMEM (code 220 KB)
  bge-01              PASS      512 KB IMEM (code 220 KB)
  bgeu-01             PASS      512 KB IMEM (code 291 KB)
  blt-01              PASS      512 KB IMEM (code 220 KB)
  bltu-01             PASS      512 KB IMEM (code 293 KB)
  bne-01              PASS      512 KB IMEM (code 220 KB)
  jal-01              SKIP      Code $\approx$`<!-- -->`{=html}1.7 MB, cần IMEM $>$`<!-- -->`{=html}2 MB
  jalr-01             PASS      Patch test case inst_7 (rd=x0 binutils bug)
  lb-align-01         PASS      DMEM preload từ .data section
  lbu-align-01        PASS      
  lh-align-01         PASS      
  lhu-align-01        PASS      
  lui-01              PASS      
  lw-align-01         PASS      
  ori-01              PASS      
  or-01               PASS      
  sb-align-01         PASS      
  sh-align-01         PASS      
  slli-01             PASS      
  sll-01              PASS      
  slti-01             PASS      
  slt-01              PASS      
  sltiu-01            PASS      
  sltu-01             PASS      
  srai-01             PASS      
  sra-01              PASS      
  srli-01             PASS      
  srl-01              PASS      
  sub-01              PASS      
  sw-align-01         PASS      
  xori-01             PASS      
  xor-01              PASS      
  **Tổng**                      **37/38 PASS; 1 SKIP (jal-01)**

  : Kết quả kiểm thử tuân thủ RV32I -- riscv-arch-test
:::
:::

Test jal-01 được phân loại là SKIP (không phải FAIL): bài kiểm thử này
thiết kế để test JAL với offset $\pm$`<!-- -->`{=html}1 MB, đòi hỏi code
size khoảng 1.7 MB -- vượt quá giới hạn thực tế của bất kỳ IMEM nhúng
nào. Lệnh JAL đã được kiểm chứng hoạt động đúng thông qua 37 chương
trình system test (mọi function call đều sử dụng JAL).

## Tổng Kết và Đánh Giá

### Tổng Hợp Kết Quả

Bảng [5.5](#tab:test-summary){reference-type="ref"
reference="tab:test-summary"} tổng hợp toàn bộ kết quả kiểm thử.

::: center
::: {#tab:test-summary}
  **Pha**      **Mô tả**                                                            **Số lượng**                       **Kết quả**
  ------------ -------------------------------------------------- ------------------------------------------------- -----------------
  Phase 1      Unit test: alu, branch_comp, regfile, id_decoder                       192 cases                       192/192 PASS
  Phase 2      Unit test: forwarding, hazard, async_fifo                              114 cases                       114/114 PASS
  Phase 3      Integration: pipeline đầy đủ (9 programs)                             9 programs                         9/9 PASS
  Phase 4a     Integration: AXI interface                                             49 cases                         49/49 PASS
  Phase 4b     Integration: AHB interface + CDC                                       29 cases                         29/29 PASS
  Phase 4c     Integration: AXI full path + 3 SFR                                     47 cases                         47/47 PASS
  Phase 4d     Integration: AHB full path + 3 SFR                                     38 cases                         38/38 PASS
  Phase 5      System: SoC + AXI/AHB SFR + IRQ (4 programs)                          4 programs                         4/4 PASS
  Phase 6a     System: batch 20 programs qua soc_top                                 20 programs                       20/20 PASS
  Phase 6b     Compliance framework (3 programs)                                     3 programs                         3/3 PASS
  Phase 7      Unit: PLIC (31) + system (3 programs)                                    31+3                         31/31+3/3 PASS
  Phase 8      Unit: EX stage (23) + CSR hazard (1)                                     23+1                         23/23+1/1 PASS
  New unit     irq_sync2ff (10), gpio_sfr (22), zicsr (38)                            70 cases                         70/70 PASS
  Bus error    AXI bus error + AHB bus error                                           4 cases                          4/4 PASS
  Compliance   riscv-arch-test RV32I                                                  38 tests                       37 PASS, 1 SKIP
  **Tổng**                                                         **$>$`<!-- -->`{=html}630 cases + 37 programs**   **Tất cả PASS**

  : Tổng hợp kết quả kiểm thử toàn dự án
:::
:::

### Bug Phát Hiện và Sửa Chữa

Trong quá trình kiểm thử, tám bug RTL và testbench đã được phát hiện và
sửa chữa. Bảng [5.6](#tab:bugs){reference-type="ref"
reference="tab:bugs"} liệt kê các bug RTL quan trọng nhất.

::: center
::: {#tab:bugs}
   **\#**  **Bug**                             **Module**      **Tác động**
  -------- ----------------------------------- --------------- -----------------------
     B3    Gap-4 RAW hazard thiếu WBR bypass   register_file   Dữ liệu sai
     B4    IMEM synchronous stall mismatch     imem            Instruction bị mất
     B5    CSR-use hazard stall quá muộn       hazard_unit     CSR read sai
     B6    Ghost instruction sau zicsr_flush   imem            Vòng lặp trap vô hạn
     B8    bus_stall + load_use → LW bị hủy    hazard_unit     Bus read không xảy ra

  : Các bug RTL quan trọng phát hiện trong quá trình kiểm thử
:::
:::

### Phân Tích Hiệu Năng Pipeline

Trong điều kiện lý tưởng (không hazard), pipeline 7 tầng đạt throughput
1 lệnh/chu kỳ (IPC = 1). Các trường hợp làm giảm IPC trong thực tế:

-   **Branch/Jump:** 2 chu kỳ flush mỗi lần rẽ nhánh (không có branch
    prediction).

-   **Load-use:** 1 chu kỳ stall mỗi lần LW theo sau ngay bởi lệnh dùng
    kết quả.

-   **CSR-use:** 1--3 chu kỳ stall tùy khoảng cách.

-   **Bus stall:** 4--6 chu kỳ cho AXI, 6--12 chu kỳ cho AHB (bao gồm
    CDC latency).

Nhờ forwarding unit hoàn chỉnh (gap-1, 2, 3, 4 không stall), các hazard
dữ liệu phổ biến nhất được xử lý miễn phí, góp phần duy trì throughput
cao trong hầu hết các tình huống thực tế.

# KẾT LUẬN {#Chapter6}

## Tóm Tắt Kết Quả Đạt Được

Khóa luận đã thiết kế và kiểm chứng thành công một hệ thống SoC RISC-V
hoàn chỉnh theo đặc tả RV32I+Zicsr với pipeline 7 tầng. Các mục tiêu đề
ra ban đầu đều được thực hiện đầy đủ:

**1. Lõi CPU pipeline 7 tầng:** CPU RV32I+Zicsr với pipeline
IF1--IF2--ID--EX--MEM1--MEM2--WB hoạt động đúng với tất cả 47 lệnh RV32I
và sáu lệnh CSR. Forwarding unit xử lý RAW hazard gap-1 đến gap-4 mà
không cần stall. Hazard unit xử lý chính xác load-use (1 stall), CSR-use
(1--3 stall), branch/jump flush (2 cycle), và bus stall (N cycle).

**2. Tích hợp bus chuẩn công nghiệp:** Hệ thống kết nối ngoại vi thông
qua cả hai giao thức AMBA -- AXI4-Lite (1 GHz, đồng bộ) và AHB-Lite
(500 MHz, bất đồng bộ qua CDC). Ba slave mỗi bus, mỗi slave triển khai
SFR Standard Register Map 9 thanh ghi.

**3. CDC an toàn:** FIFO bất đồng bộ độ sâu 2 với con trỏ Gray code
truyền dữ liệu an toàn giữa miền 1 GHz và 500 MHz. IRQ từ AHB domain
được đồng bộ qua module 2-FF synchronizer riêng biệt.

**4. PLIC và Zicsr:** PLIC 6 nguồn tương thích chuẩn SiFive với
priority, threshold và claim/complete. Zicsr xử lý đầy đủ ngắt ngoại lệ
M-mode với vectored interrupt mode và precise exception semantics.

**5. Kiểm chứng toàn diện:** Hơn 630 test case tự kiểm tra cộng với 37
chương trình hệ thống, tất cả PASS. Bộ kiểm thử tuân thủ chính thức
RV32I đạt 37/38 PASS (1 SKIP do giới hạn phần cứng của bài kiểm thử
jal-01).

**6. SFR Standard Register Map:** Chuẩn hóa giao diện ngoại vi theo mô
hình OpenTitan-inspired cho phép bất kỳ ngoại vi tuân thủ chuẩn đều có
thể kết nối vào SoC mà không cần sửa RTL lõi.

## Hạn Chế

Dù đạt được các mục tiêu đề ra, thiết kế còn một số hạn chế cần thừa
nhận:

-   **Không có branch prediction:** Pipeline phải flush 2 chu kỳ mỗi khi
    branch taken. Với workload có nhiều branch (như vòng lặp), IPC thực
    tế thấp hơn lý thuyết. Thêm static prediction (predict not-taken)
    hoặc dynamic prediction sẽ cải thiện đáng kể.

-   **IMEM/DMEM không có cache:** Mọi lệnh và dữ liệu đều truy cập trực
    tiếp SRAM 1 chu kỳ. Trong hệ thống thực, bộ nhớ ngoài có latency cao
    hơn nhiều, đòi hỏi cache để duy trì throughput.

-   **Chưa tổng hợp vật lý:** Thiết kế chỉ được kiểm chứng ở mức RTL mô
    phỏng. Tần số 1 GHz là mục tiêu thiết kế; việc đạt được tần số này
    trên công nghệ ASIC cụ thể phụ thuộc vào kết quả timing analysis sau
    synthesis và place-and-route.

-   **Bộ lệnh giới hạn ở RV32I:** Không hỗ trợ nhân/chia (M extension),
    nguyên tử (A extension), hay dấu phẩy động (F/D). Đây là giới hạn có
    chủ ý để giữ phạm vi phù hợp với khóa luận cử nhân.

-   **jal-01 không kiểm thử được qua framework:** Bài kiểm thử jal-01
    trong riscv-arch-test yêu cầu IMEM $>$`<!-- -->`{=html}1.7 MB --
    không khả thi cho SoC nhúng. Tuy nhiên, lệnh JAL đã được kiểm chứng
    đầy đủ qua 37 chương trình system test.

## Hướng Phát Triển

Dựa trên nền tảng đã xây dựng, có một số hướng phát triển tiếp theo có
tiềm năng cao:

-   **Tổng hợp vật lý và timing closure:** Sử dụng Yosys + OpenSTA hoặc
    công cụ thương mại (Synopsys DC, Cadence Genus) để tổng hợp design,
    phân tích timing và đảm bảo closure ở 1 GHz trên công nghệ 130nm
    hoặc 28nm.

-   **Thêm branch predictor:** Triển khai BTB (Branch Target Buffer) và
    BHT (Branch History Table) để giảm branch penalty từ 2 xuống 0--1
    cycle trong trường hợp predict đúng.

-   **Phần mở rộng M (Multiply/Divide):** Thêm khối nhân/chia tích hợp
    tại tầng EX hoặc WB để hỗ trợ RV32IM -- cần thiết cho các thuật toán
    số học phức tạp.

-   **Cache L1 I\$ và D\$:** Thêm instruction cache và data cache để kết
    nối với bộ nhớ ngoài DRAM mà không hy sinh throughput pipeline.

-   **Hỗ trợ FPGA:** Đưa design lên board phát triển (Arty A7, Nexys A7)
    để kiểm chứng phần cứng thực, bao gồm tích hợp với IP ngoại vi thực
    tế như UART, SPI, GPIO trên chip FPGA.

-   **Formal verification:** Áp dụng công cụ verification hình thức (như
    SymbiYosys) để chứng minh các bất biến pipeline (invariants) như
    precise exception luôn đúng, không bao giờ có data corruption.
