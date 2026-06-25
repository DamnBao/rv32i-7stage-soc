# Compliance Tasks — RV32I riscv-arch-test

Ngày: 2026-06-25  
Trạng thái hiện tại: 30/30 PASS (eligible); 7 SKIP IMEM overflow; 1 N/A jalr-01 bug

---

## Task A — Fix branch compliance tests (6 tests) ✅ DONE (2026-06-25)

**Mục tiêu:** 30 → 36 PASS; jal-01 vẫn SKIP

**Nguyên nhân skip:** Branch tests (beq-01, bge-01, bgeu-01, blt-01, bltu-01, bne-01) sinh ~220KB code
do test vector dày đặc — vượt quá 64KB IMEM phần cứng.

**Giải pháp:** Parameterize IMEM DEPTH, override lên 256KB trong compliance testbench.
Hardware SoC production vẫn dùng 64KB (default). Không ảnh hưởng RTL synthesis.

**Thực tế thực hiện:**
- `imem.sv` đã có `parameter SIZE_KB=64` sẵn → không cần đổi
- `RTL/soc_top.sv`: thêm `parameter IMEM_SIZE_KB = 64`, pass xuống `u_imem`
- `SIM/compliance/tb_compliance_run.sv`: instantiate `soc_top #(.IMEM_SIZE_KB(512))`
- `SIM/compliance/link_compliance.ld`: `LENGTH = 512K`
- `SIM/compliance/run_compliance.sh`: thêm `-Wl,--no-check-sections` (Harvard arch: IMEM/DMEM là 2 mảng độc lập nên linker LMA overlap check là false alarm); `IMEM_MAX=524288`
- Cần 512KB vì bgeu-01 (291KB) và bltu-01 (293KB) vượt 256KB

**Kết quả thực tế:**
| | Trước | Sau |
|--|-------|-----|
| PASS | 30 | **36** |
| SKIP (IMEM) | 7 | 1 (jal-01 ~1.7MB) |
| N/A | 1 | 1 (jalr-01 bug) |

---

## Task B — Fix jalr-01 (1 test) 🔲 TODO

**Mục tiêu:** 36 → 37 PASS; jal-01 vẫn SKIP

**Nguyên nhân fail:** `TEST_JALR_OP` macro (arch_test.h dòng 707) sinh `la x0, 5b`
khi `rd=x0`. Binutils ≥2.39 reject vì x0 là zero register.

**Giải pháp:** Patch `SIM/compliance/tests/src/jalr-01.S` dòng 72:
thay test case `TEST_JALR_OP(x15, x0, x31, 0x20, x10, 28, 0)` bằng một test case
dùng register hợp lệ (e.g. `x30` thay `x0`), hoặc xóa test case đó.

**Lưu ý:** `jalr x0, imm(rs)` (jump không link) đã được verify qua system programs
(dùng `ret` = `jalr x0, 0(ra)` rộng rãi). Patch này chỉ để hoàn thiện compliance.

**Các bước:**
1. Xem `jalr-01.S` dòng 70-72: `TEST_JALR_OP(x15, x0, x31, 0x20, x10, 28, 0)`
2. Thay `x0` bằng `x30` (hoặc register chưa dùng), tạo reference output mới
3. Hoặc xóa dòng đó nếu reference output của Spike đã được gen với `x0` → cần regen reference
4. Chạy `make rv32i_compliance`, kỳ vọng 37/38 PASS

**Rủi ro:** Nếu patch register, reference output phải được regen với Spike (vì giá trị x30 ≠ x0).
Cần cẩn thận giữ nguyên test intent.

---

## Task C — Update CLAUDE.md 🔲 TODO (sau A+B)

Sau khi Task A+B hoàn thành:
- Cập nhật dòng `rv32i_compliance` trong testing table:
  `37/38 PASS; 1 SKIP (jal-01 ~1.7MB code, cần 2MB IMEM)`
- Commit toàn bộ

---

## Ghi chú kỹ thuật

- **jal-01 không fix được thực tế:** code ~1.7MB, cần IMEM ~2MB — không phù hợp embedded SoC
- **Branch behavior đã verify:** Phase 3 `prog_branch_jump.hex` + Phase 6 20 programs dùng branch
- **JALR verify:** mọi function call/return trong system programs dùng JALR (jal→jalr x0 ret)
- **IMEM parameterization không ảnh hưởng synthesis:** `parameter` với default 16384 giữ nguyên behavior
