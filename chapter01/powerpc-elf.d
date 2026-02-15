/*
 * powerpc-elf (ELF32 PowerPC) の逆アセンブル結果に「詳細コメント」を付けた版。
 *
 * この出力は、先ほどの C 関数群を PowerPC 32bit 向けにコンパイルしたときの
 * 典型的な命令列になっている。
 *
 * ----------------------------
 * PowerPC 32bit ABI（ざっくり）
 * ----------------------------
 * - 戻り値（整数/ポインタ）: r3
 * - 引数:
 *     第1引数: r3
 *     第2引数: r4
 *     第3引数: r5
 *     ...
 *   （多引数は r3,r4,r5,... に順に入るのが基本。今回の many_args は r10 まで使っている）
 * - LR (Link Register):
 *     bl/blr/blrl で戻り先アドレスを保持する専用レジスタ。
 *     関数内でさらに別関数を呼ぶ場合（= LR を上書きする場合）は、
 *     LR を退避してから呼び出し、復帰時に戻す必要がある。
 * - スタックポインタ: r1
 * - 典型的なスタック確保:
 *     stwu r1, -N(r1)   ; r1 = r1 - N して、その値を（古いr1の場所に）保存する “更新付き store”
 *   典型的な解放:
 *     addi r1, r1, N
 *
 * ----------------------------
 * 主要命令の読み方（今回よく出るもの）
 * ----------------------------
 * - blr        : branch to link register（return）
 * - li rD,imm  : load immediate（16bit範囲の即値を rD に）
 * - lis rD,imm : load immediate shifted（imm << 16 を rD に入れる）
 * - ori rA,rS,imm : rA = rS | imm（下位16bitの埋め合わせに使われる）
 * - mr rA,rS   : move register（実体は or rA,rS,rS）
 * - add / addi : 加算（addi は即値）
 * - lwz/stw    : load/store word (4byte) with zero-extend（実質32bitロード/ストア）
 * - mflr/mtlr  : LR の読み出し/書き込み
 * - bl         : branch and link（call、LRを更新）
 * - blrl       : branch to LR and link（関数ポインタ呼び出しでよく出る）
 * - cmpw crX,rA,rB : 32bit比較結果を指定CRフィールドに置く（ここでは cr7 を使っている）
 * - bne+/blt+/bgelr : 条件分岐（+ は “予測ヒント” の意味合い）
 *
 * 以降、各関数ごとに「Cの意味 → この命令列でどう実現しているか」を説明する。
 */

Disassembly of section .text:

00fe1400 <null>:
  fe1400:  4e 80 00 20    blr
  ; null():
  ;   何もしないので、そのまま return。
  ; 観察ポイント:
  ;   PowerPC では “return” が blr（LRへ分岐）1命令で終わることが多い。

00fe1404 <return_zero>:
  fe1404:  38 60 00 00    li      r3,0
  fe1408:  4e 80 00 20    blr
  ; return_zero():
  ;   戻り値レジスタ r3 に 0 を入れて return。
  ; 観察ポイント:
  ;   x86 の xor eax,eax に相当する “0を返す” の最短形は li r3,0。

00fe140c <return_one>:
  fe140c:  38 60 00 01    li      r3,1
  fe1410:  4e 80 00 20    blr
  ; return_one():
  ;   r3=1, return。

00fe1414 <return_int_size>:
  fe1414:  38 60 00 04    li      r3,4
  fe1418:  4e 80 00 20    blr
  ; return_int_size():
  ;   sizeof(int)=4 (このターゲット環境では int が 32bit)
  ; 観察ポイント:
  ;   sizeof はコンパイル時定数なので命令列は “即値ロード + return” だけになる。

00fe141c <return_pointer_size>:
  fe141c:  38 60 00 04    li      r3,4
  fe1420:  4e 80 00 20    blr
  ; return_pointer_size():
  ;   sizeof(int*)=4 → 32bitアドレス空間（ELF32 PowerPC）であることが分かる。
  ; 観察ポイント:
  ;   64bitターゲットならここは 8 になる。

00fe1424 <return_short_size>:
  fe1424:  38 60 00 02    li      r3,2
  fe1428:  4e 80 00 20    blr
  ; return_short_size():
  ;   sizeof(short)=2

00fe142c <return_long_size>:
  fe142c:  38 60 00 04    li      r3,4
  fe1430:  4e 80 00 20    blr
  ; return_long_size():
  ;   sizeof(long)=4
  ; 観察ポイント:
  ;   この環境は long=4（ILP32寄り）である。
  ;   x86-64 Linux(LP64) の “long=8” とは違う。

00fe1434 <return_short>:
  fe1434:  38 60 77 88    li      r3,30600
  fe1438:  4e 80 00 20    blr
  ; return_short():
  ;   C: return (short)0x7788;
  ;   PPC: r3 に 0x7788 を入れて返す。
  ;
  ; 観察ポイント:
  ;   short を返す関数でも ABI の戻り値は r3（32bit）なので、
  ;   “結果は r3 に載る” という形になる（下位16bitが意味を持つ）。
  ;   どこで 16bit化/符号拡張が起きるかは「呼び出し側がどう扱うか」で決まる。

00fe143c <return_long>:
  fe143c:  3c 60 77 88    lis     r3,30600
  fe1440:  60 63 99 aa    ori     r3,r3,39338
  fe1444:  4e 80 00 20    blr
  ; return_long():
  ;   32bit即値 0x778899aa を作る典型パターン。
  ;   - lis r3,0x7788      → r3 = 0x7788_0000
  ;   - ori r3,r3,0x99aa   → r3 = 0x7788_99aa
  ;   で 32bit定数を合成している。
  ;
  ; 観察ポイント:
  ;   PPC は “一命令で32bit即値をロード” できないので、
  ;   上位16bit(lis) + 下位16bit(ori) の2段構えが定番。

00fe1448 <return_short_upper>:
  fe1448:  38 60 ff ee    li      r3,-18
  fe144c:  4e 80 00 20    blr
  ; return_short_upper():
  ;   0xffee は signed 16bit だと -18。
  ;   li は “符号付き16bit即値” を r3 にロードするので、アセンブラ表示は -18 になる。
  ;
  ; 観察ポイント:
  ;   0xffee を「符号付き」として扱っていることが表示から読める。
  ;   ただし r3 のビット表現としては 0xFFFF_FFEE になる。

00fe1450 <return_long_upper>:
  fe1450:  3c 60 ff ee    lis     r3,-18
  fe1454:  60 63 dd cc    ori     r3,r3,56780
  fe1458:  4e 80 00 20    blr
  ; return_long_upper():
  ;   0xffeeddcc を lis+ori で構成。
  ;   - lis r3,0xffee → r3 = 0xffee_0000（ここで “-18<<16” と等価）
  ;   - ori r3,r3,0xddcc → r3 = 0xffee_ddcc
  ;
  ; 観察ポイント:
  ;   “上位16bitが負に見える” のは、即値を符号付きで解釈して表示しているため。
  ;   ビット列としては狙い通り 0xffeeddcc が出来ている。

00fe145c <return_arg1>:
  fe145c:  4e 80 00 20    blr
  ; return_arg1(int a):
  ;   C: return a;
  ;   ABI: 第1引数 a は r3 に入ってくる。
  ;   つまり「すでに戻り値レジスタ r3 に値がある」ので何もしなくて良い → そのまま blr。
  ;
  ; 観察ポイント:
  ;   “引数レジスタと戻り値レジスタが同じ” だと、return a は命令ゼロで成立する。

00fe1460 <return_arg2>:
  fe1460:  7c 83 23 78    mr      r3,r4
  fe1464:  4e 80 00 20    blr
  ; return_arg2(int a,int b):
  ;   a=r3, b=r4。戻り値は r3。
  ;   b を返すために r4→r3 へ移して return。
  ;
  ; mr r3,r4 は実体として:
  ;   or r3,r4,r4
  ; という “同じ値ORでコピー” の定石。
  ;
  ; 観察ポイント:
  ;   2番目引数の位置が r4 であることがここから分かる。

00fe1468 <add>:
  fe1468:  7c 63 22 14    add     r3,r3,r4
  fe146c:  4e 80 00 20    blr
  ; add(int a,int b):
  ;   a=r3, b=r4。
  ;   add r3,r3,r4 で “a+b を r3 に上書き” → 戻り値完成。
  ;
  ; 観察ポイント:
  ;   PPC の add は3オペランド形式（dest,src1,src2）で書けるので
  ;   “そのまま戻り値レジスタに計算結果を置く” が自然。

00fe1470 <add3>:
  fe1470:  7c 83 22 14    add     r4,r3,r4
  fe1474:  7c 64 2a 14    add     r3,r4,r5
  fe1478:  4e 80 00 20    blr
  ; add3(int a,int b,int c):
  ;   a=r3, b=r4, c=r5。
  ;   1) r4 = r3 + r4   ; (a+b) を一旦 r4 に
  ;   2) r3 = r4 + r5   ; (a+b)+c を戻り値 r3 に
  ;
  ; 観察ポイント:
  ;   “一時値” をどのレジスタに置くかはコンパイラ都合で変わる。
  ;   今回は r4 をテンポラリに使っている。

00fe147c <add_two>:
  fe147c:  38 63 00 02    addi    r3,r3,2
  fe1480:  4e 80 00 20    blr
  ; add_two(int a):
  ;   addi は “即値加算”。
  ;   a=r3 に 2 を足して r3 に戻す → return。

00fe1484 <inc>:
  fe1484:  38 63 00 01    addi    r3,r3,1
  fe1488:  4e 80 00 20    blr
  ; inc(int a):
  ;   前置++だが戻り値だけ見れば a+1。
  ;   addi r3,r3,1 で終了。

00fe148c <or>:
  fe148c:  7c 63 23 78    or      r3,r3,r4
  fe1490:  4e 80 00 20    blr
  ; or(int a,int b):
  ;   r3 = r3 OR r4 → return。

00fe1494 <or_one>:
  fe1494:  60 63 00 01    ori     r3,r3,1
  fe1498:  4e 80 00 20    blr
  ; or_one(int a):
  ;   下位ビットを立てる典型。
  ;   ori は “即値OR（下位16bit）”。

00fe149c <load>:
  fe149c:  80 63 00 00    lwz     r3,0(r3)
  fe14a0:  4e 80 00 20    blr
  ; load(volatile int *p):
  ;   p=r3（アドレス）。*p を読む。
  ;   lwz r3,0(r3) でメモリ[r3]の32bitをロードして r3 に入れる。
  ;
  ; 観察ポイント:
  ;   volatile のため、このロードは最適化で消えにくい。

00fe14a4 <store>:
  fe14a4:  38 00 00 ff    li      r0,255
  fe14a8:  90 03 00 00    stw     r0,0(r3)
  fe14ac:  4e 80 00 20    blr
  ; store(volatile int *p):
  ;   *p = 0xff
  ;   1) li r0,255 で即値を作る（戻り値r3はポインタ保持に使いたいので r0 を使う）
  ;   2) stw r0,0(r3) でメモリにストア
  ;
  ; 観察ポイント:
  ;   r0 は “テンポラリ” としてよく使われる（ABI/コンパイラ規約で特別扱いされることもある）。

00fe14b0 <load_long>:
  fe14b0:  80 63 00 00    lwz     r3,0(r3)
  fe14b4:  4e 80 00 20    blr
  ; load_long(volatile long *p):
  ;   long=4 の環境なので load と同じ lwz になっている。
  ;
  ; 観察ポイント:
  ;   “long=4” の証拠がここでも再確認できる。

00fe14b8 <store_long>:
  fe14b8:  3c 00 11 22    lis     r0,4386
  fe14bc:  60 00 33 44    ori     r0,r0,13124
  fe14c0:  90 03 00 00    stw     r0,0(r3)
  fe14c4:  4e 80 00 20    blr
  ; store_long(volatile long *p):
  ;   *p = 0x11223344
  ;   32bit即値は lis+ori で合成してから stw。
  ;   1) r0 = 0x1122_0000
  ;   2) r0 = r0 | 0x3344 = 0x1122_3344
  ;   3) store
  ;
  ; 観察ポイント:
  ;   “即値が大きい” と li では収まらない → lis/ori になる。

00fe14c8 <member>:
  fe14c8:  38 00 00 01    li      r0,1
  fe14cc:  90 03 00 04    stw     r0,4(r3)
  fe14d0:  80 63 00 08    lwz     r3,8(r3)
  fe14d4:  4e 80 00 20    blr
  ; member(struct structure *p):
  ;   p=r3
  ;   p->b=1  → offset 4 に stw
  ;   return p->c → offset 8 を lwz して r3 に置く
  ;
  ; 観察ポイント:
  ;   構造体は “ベース + オフセット” で丸見えになる。
  ;   a:0, b:4, c:8 という綺麗な並びがそのまま命令に現れる。

00fe14d8 <get_static_value_addr>:
  fe14d8:  3c 60 00 fe    lis     r3,254
  fe14dc:  38 63 18 00    addi    r3,r3,6144
  fe14e0:  4e 80 00 20    blr
  ; get_static_value_addr():
  ;   &static_value のアドレスを返す。
  ;
  ; 典型的な絶対アドレス構成:
  ;   r3 = 0x00fe_0000 (lis r3,0xfe)
  ;   r3 = r3 + 0x1800 (addi)
  ;   → r3 = 0x00fe_1800
  ;
  ; 観察ポイント:
  ;   PIC(位置独立)よりも “絶対アドレス合成” っぽい形になっている。
  ;   リンカ配置が 0x00fe1800 付近に static_value を置いたと推測できる。

00fe14e4 <get_static_value>:
  fe14e4:  3d 20 00 fe    lis     r9,254
  fe14e8:  80 69 18 00    lwz     r3,6144(r9)
  fe14ec:  4e 80 00 20    blr
  ; get_static_value():
  ;   static_value をロードして返す。
  ;
  ; 1) r9 = 0x00fe_0000
  ; 2) r3 = mem32[r9 + 0x1800]
  ;
  ; 観察ポイント:
  ;   - ベースレジスタに r9 を使い、disp(16bit)で下位を表現している
  ;   - “グローバル参照 = (上位ロード + disp付きlwz)” はPPCの定番。

00fe14f0 <set_static_value>:
  fe14f0:  3d 20 00 fe    lis     r9,254
  fe14f4:  90 69 18 00    stw     r3,6144(r9)
  fe14f8:  4e 80 00 20    blr
  ; set_static_value(int a):
  ;   a は r3。
  ;   r9でベース作って stw r3,disp(r9)。
  ;
  ; 観察ポイント:
  ;   引数レジスタ r3 をそのまま store に使っている（ムダな移動がない）。

00fe14fc <set_stack>:
  fe14fc:  94 21 ff f0    stwu    r1,-16(r1)
  fe1500:  38 00 00 fe    li      r0,254
  fe1504:  90 01 00 08    stw     r0,8(r1)
  fe1508:  38 00 00 ff    li      r0,255
  fe150c:  90 01 00 0c    stw     r0,12(r1)
  fe1510:  38 21 00 10    addi    r1,r1,16
  fe1514:  4e 80 00 20    blr
  ; set_stack():
  ;   volatile なローカル a,b を “確実にスタックへ書く” 例。
  ;
  ; スタック確保:
  ;   stwu r1,-16(r1)
  ;     - r1 = r1 - 16
  ;     - さらに “更新後のr1” を元のスタックに書く、というPPC特有のプロローグ命令
  ;
  ; ローカル配置（この関数では）:
  ;   [r1+8]  = a (0xfe)
  ;   [r1+12] = b (0xff)
  ;
  ; スタック解放:
  ;   addi r1,r1,16
  ; return:
  ;   blr
  ;
  ; 観察ポイント:
  ;   - volatile により “ストアが消えない”
  ;   - ローカルは r1 基準の固定オフセットで見える

00fe1518 <use_stack>:
  fe1518:  94 21 ff f0    stwu    r1,-16(r1)
  fe151c:  38 00 00 fe    li      r0,254
  fe1520:  90 01 00 08    stw     r0,8(r1)
  fe1524:  38 00 00 ff    li      r0,255
  fe1528:  90 01 00 0c    stw     r0,12(r1)
  fe152c:  80 01 00 08    lwz     r0,8(r1)
  fe1530:  80 61 00 0c    lwz     r3,12(r1)
  fe1534:  7c 60 1a 14    add     r3,r0,r3
  fe1538:  38 21 00 10    addi    r1,r1,16
  fe153c:  4e 80 00 20    blr
  ; use_stack():
  ;   a,b をスタックに置き、読み戻して加算して返す。
  ;
  ; 1) スタック確保（-16）
  ; 2) a=0xfe を [r1+8] に store
  ; 3) b=0xff を [r1+12]に store
  ; 4) a を r0 に load
  ; 5) b を r3 に load（戻り値レジスタに直接入れる）
  ; 6) r3 = r0 + r3
  ; 7) スタック解放、return
  ;
  ; 観察ポイント:
  ;   - volatile のため “store→load” が必ず残る（レジスタ最適化されにくい）
  ;   - 戻り値レジスタ r3 を最後の計算結果置き場として活用している

00fe1540 <call_self>:
  fe1540:  94 21 ff f0    stwu    r1,-16(r1)
  fe1544:  7c 08 02 a6    mflr    r0
  fe1548:  90 01 00 14    stw     r0,20(r1)
  fe154c:  4b ff ff f5    bl      fe1540 <call_self>
  fe1550:  80 01 00 14    lwz     r0,20(r1)
  fe1554:  7c 08 03 a6    mtlr    r0
  fe1558:  38 21 00 10    addi    r1,r1,16
  fe155c:  4e 80 00 20    blr
  ; call_self():
  ;   無限再帰。PPCでは call=bl。
  ;
  ; なぜ LR の退避が必要か:
  ;   bl は「次命令アドレス」を LR に書く。
  ;   この関数内で bl を実行すると LR が上書きされるため、
  ;   復帰用の LR を保持したければスタックに退避する必要がある。
  ;
  ; 命令の流れ:
  ;   1) スタック確保
  ;   2) mflr r0         ; LR→r0
  ;   3) stw r0,20(r1)   ; LR退避（注意: r1 は -16 済みなので +20 は “確保領域の外側” に見えるが、
  ;                        これはABIのフレームレイアウト（back chain/保存領域）都合でよくある）
  ;   4) bl call_self    ; 再帰呼び出し（LR上書き）
  ;   5) lwz r0,20(r1)
  ;   6) mtlr r0         ; LR復元
  ;   7) スタック解放
  ;   8) blr             ; return
  ;
  ; 観察ポイント:
  ;   “関数内でcallするならLRを保存” がPPCの基本。

00fe1560 <call_simple>:
  fe1560:  94 21 ff f0    stwu    r1,-16(r1)
  fe1564:  7c 08 02 a6    mflr    r0
  fe1568:  90 01 00 14    stw     r0,20(r1)
  fe156c:  4b ff fe f1    bl      fe145c <return_arg1>
  fe1570:  80 01 00 14    lwz     r0,20(r1)
  fe1574:  7c 08 03 a6    mtlr    r0
  fe1578:  38 21 00 10    addi    r1,r1,16
  fe157c:  4e 80 00 20    blr
  ; call_simple(int a):
  ;   return return_arg1(a);
  ;   a はすでに r3 に入っているので、引数セットは不要。
  ;
  ; ただし call するので LR を保存→復元している。
  ;
  ; 観察ポイント:
  ;   - 引数受け渡しはゼロ命令（r3そのまま）
  ;   - call のための LR セーブ/リストアが “最小の関数呼び出し雛形” になっている

00fe1580 <call_complex1>:
  fe1580:  94 21 ff f0    stwu    r1,-16(r1)
  fe1584:  7c 08 02 a6    mflr    r0
  fe1588:  90 01 00 14    stw     r0,20(r1)
  fe158c:  38 60 00 fe    li      r3,254
  fe1590:  4b ff fe cd    bl      fe145c <return_arg1>
  fe1594:  38 63 00 01    addi    r3,r3,1
  fe1598:  80 01 00 14    lwz     r0,20(r1)
  fe159c:  7c 08 03 a6    mtlr    r0
  fe15a0:  38 21 00 10    addi    r1,r1,16
  fe15a4:  4e 80 00 20    blr
  ; call_complex1():
  ;   return return_arg1(0xfe) + 1;
  ;
  ; 1) r3 = 0xfe をセット（第1引数）
  ; 2) bl return_arg1
  ; 3) 戻り値 r3 に +1（addi）
  ; 4) return
  ;
  ; 観察ポイント:
  ;   “戻り値を受けた r3 にそのまま後続演算” が素直に見える。

00fe15a8 <call_complex2>:
  fe15a8:  94 21 ff e0    stwu    r1,-32(r1)
  fe15ac:  7c 08 02 a6    mflr    r0
  fe15b0:  93 a1 00 14    stw     r29,20(r1)
  fe15b4:  90 01 00 24    stw     r0,36(r1)
  fe15b8:  7c 9d 23 78    mr      r29,r4
  fe15bc:  7c 83 23 78    mr      r3,r4
  fe15c0:  4b ff fe 9d    bl      fe145c <return_arg1>
  fe15c4:  3d 20 00 fe    lis     r9,254
  fe15c8:  90 69 18 00    stw     r3,6144(r9)
  fe15cc:  7f a3 eb 78    mr      r3,r29
  fe15d0:  80 01 00 24    lwz     r0,36(r1)
  fe15d4:  7c 08 03 a6    mtlr    r0
  fe15d8:  83 a1 00 14    lwz     r29,20(r1)
  fe15dc:  38 21 00 20    addi    r1,r1,32
  fe15e0:  4e 80 00 20    blr
  ; call_complex2(int a,int b):
  ;   C:
  ;     static_value = return_arg1(b);
  ;     return b;
  ;
  ; ABI:
  ;   a=r3, b=r4 で入ってくる（注意: PPCでは第1引数がr3なので a がr3、b がr4）
  ;
  ; 命令の流れ:
  ;   1) stwu r1,-32(r1)     ; 余裕を持ってフレーム確保（LR保存+callee-saved保存のため）
  ;   2) mflr r0 / stw r0,...; LR保存（callがあるので必須）
  ;   3) stw r29,...         ; r29 は “callee-saved” 側（呼び出し側に壊してはいけない）として使われがち
  ;   4) mr r29,r4           ; b を r29 に退避（この後 call で r4 が変わる可能性や、後で b を返すため）
  ;   5) mr r3,r4            ; return_arg1 の第1引数は r3 なので、b を r3 に移す
  ;   6) bl return_arg1      ; 戻り値は r3
  ;   7) lis r9,0xfe         ; static_value ベース
  ;   8) stw r3,0x1800(r9)   ; static_value = r3（return_arg1(b) の結果）
  ;   9) mr r3,r29           ; return b のため、保存しておいた b を r3 に戻す
  ;  10) LR復元、r29復元、スタック解放、blr
  ;
  ; 観察ポイント:
  ;   - “引数の付け替え” (b:r4 → r3) が明確に出る
  ;   - b を返すので b を callee-saved レジスタ r29 に確保している（値の生存期間の都合）
  ;   - グローバル書き込みが lis+disp(stw) で表現される

00fe15e4 <call_pointer>:
  fe15e4:  94 21 ff f0    stwu    r1,-16(r1)
  fe15e8:  7c 08 02 a6    mflr    r0
  fe15ec:  90 01 00 14    stw     r0,20(r1)
  fe15f0:  7c 68 03 a6    mtlr    r3
  fe15f4:  4e 80 00 21    blrl
  fe15f8:  80 01 00 14    lwz     r0,20(r1)
  fe15fc:  7c 08 03 a6    mtlr    r0
  fe1600:  38 21 00 10    addi    r1,r1,16
  fe1604:  4e 80 00 20    blr
  ; call_pointer(int (*f)(void)):
  ;   C: f();
  ;   f は第1引数なので r3 に入っている（関数アドレス）。
  ;
  ; PPC の間接呼び出しは典型的に:
  ;   mtlr r3    ; LR に “呼び出したい関数アドレス” を入れる
  ;   blrl       ; LRへ分岐しつつ、戻り先を新しいLRにセット（call相当）
  ;
  ; ただし blrl 自体が LR を更新するので、
  ; “元のLR（この関数の戻り先）” は事前にスタックへ退避している。
  ;
  ; 観察ポイント:
  ;   - 関数ポインタ呼び出しが “mtlr + blrl” で表現される
  ;   - LR の保存が必須（戻れなくなるため）

00fe1608 <condition>:
  fe1608:  7f 83 20 00    cmpw    cr7,r3,r4
  fe160c:  40 be 00 08    bne+    cr7,fe1614 <condition+0xc>
  fe1610:  38 80 00 01    li      r4,1
  fe1614:  38 64 00 01    addi    r3,r4,1
  fe1618:  4e 80 00 20    blr
  ; condition(int a,int b):
  ;   C:
  ;     if (a==b) b=1;
  ;     return b+1;
  ;
  ; ABI:
  ;   a=r3, b=r4
  ;
  ; 1) cmpw cr7,r3,r4
  ;      - r3 と r4 を 32bit比較し、結果を CR7 フィールドに格納
  ; 2) bne+ cr7, label
  ;      - “等しくないなら” if本体を飛ばす
  ; 3) li r4,1
  ;      - 等しい場合だけ b=1（bはr4で表現）
  ; 4) addi r3,r4,1
  ;      - 戻り値r3に (b+1) を置く
  ;
  ; 観察ポイント:
  ;   - 比較結果は CR に入り、分岐命令が CR を参照する
  ;   - b を r4 のまま保持し、最後に r3 に結果を作る（戻り値はr3）

00fe161c <loop>:
  fe161c:  7c 60 1b 78    mr      r0,r3
  fe1620:  38 60 00 00    li      r3,0
  fe1624:  39 20 00 00    li      r9,0
  fe1628:  7f 83 00 00    cmpw    cr7,r3,r0
  fe162c:  4c 9c 00 20    bgelr   cr7
  fe1630:  7c 63 4a 14    add     r3,r3,r9
  fe1634:  39 29 00 01    addi    r9,r9,1
  fe1638:  7f 89 00 00    cmpw    cr7,r9,r0
  fe163c:  41 9c ff f4    blt+    cr7,fe1630 <loop+0x14>
  fe1640:  4e 80 00 20    blr
  ; loop(int n):
  ;   C:
  ;     int i,sum=0;
  ;     for(i=0;i<n;i++) sum+=i;
  ;     return sum;
  ;
  ; ABI:
  ;   n は r3 で入ってくるが、sum も戻り値で r3 を使いたい。
  ;   そのため最初に n を r0 に退避している。
  ;
  ; 命令の意味:
  ;   mr r0,r3        ; r0 = n（nを退避）
  ;   li r3,0         ; sum = 0（戻り値レジスタをsumとして再利用）
  ;   li r9,0         ; i = 0（ここでは i を r9 で管理）
  ;
  ;   cmpw cr7,r3,r0  ; sum(=0) と n を比較しているように見えるが、
  ;                   ; ここは “0 >= n なら即return” を作りたいだけなので
  ;                   ; 0 を持っている r3 を比較に流用している。
  ;   bgelr cr7       ; (0 >= n) なら return（LRへ分岐）→ ループ自体をスキップ
  ;
  ; .Lloop:
  ;   add r3,r3,r9    ; sum += i
  ;   addi r9,r9,1    ; i++
  ;   cmpw cr7,r9,r0  ; i < n ?
  ;   blt  .Lloop     ; i < n なら続行
  ;   blr             ; ループ終了で return sum
  ;
  ; 観察ポイント:
  ;   - n を r0 に退避して、r3 を sum として使う（戻り値レジスタ再利用の典型）
  ;   - “bgelr” は分岐先が lr になっていて、早期returnを1命令で実現できる
  ;   - i のためのレジスタ選択（r9）はコンパイラ都合で変わる

00fe1644 <many_args>:
  fe1644:  7c c3 32 14    add     r6,r3,r6
  fe1648:  7c c6 42 14    add     r6,r6,r8
  fe164c:  7c 66 52 14    add     r3,r6,r10
  fe1650:  4e 80 00 20    blr
  ; many_args(a0..a7):
  ;   C: return a0 + a3 + a5 + a7;
  ;
  ; ここでのレジスタ対応が非常に重要（このコンパイル結果は次の対応になっている）:
  ;   a0 = r3
  ;   a1 = r4
  ;   a2 = r5
  ;   a3 = r6
  ;   a4 = r7
  ;   a5 = r8
  ;   a6 = r9
  ;   a7 = r10
  ;
  ; なので:
  ;   add r6,r3,r6   ; r6 = a0 + a3
  ;   add r6,r6,r8   ; r6 = (a0+a3) + a5
  ;   add r3,r6,r10  ; r3 = (a0+a3+a5) + a7（戻り値完成）
  ;   blr
  ;
  ; 観察ポイント:
  ;   - PPCでは引数が多くても、かなりの数がレジスタで渡されることがある（ABI/オプション依存もあり得る）
  ;   - “戻り値 r3 に最後にまとめる” が綺麗に見える
  ;   - a1,a2,a4,a6 は使わないので命令に現れない（未使用引数）

00fe1654 <call_many_args>:
  fe1654:  94 21 ff f0    stwu    r1,-16(r1)
  fe1658:  7c 08 02 a6    mflr    r0
  fe165c:  90 01 00 14    stw     r0,20(r1)
  fe1660:  38 60 00 00    li      r3,0
  fe1664:  38 80 00 01    li      r4,1
  fe1668:  38 a0 00 02    li      r5,2
  fe166c:  38 c0 00 03    li      r6,3
  fe1670:  38 e0 00 04    li      r7,4
  fe1674:  39 00 00 05    li      r8,5
  fe1678:  39 20 00 06    li      r9,6
  fe167c:  39 40 00 07    li      r10,7
  fe1680:  4b ff ff c5    bl      fe1644 <many_args>
  fe1684:  80 01 00 14    lwz     r0,20(r1)
  fe1688:  7c 08 03 a6    mtlr    r0
  fe168c:  38 21 00 10    addi    r1,r1,16
  fe1690:  4e 80 00 20    blr
  ; call_many_args():
  ;   C: return many_args(0,1,2,3,4,5,6,7);
  ;
  ; 1) call するので LR を保存
  ; 2) 引数を r3..r10 に順に即値セット（上で読み取ったレジスタ割当と一致）
  ; 3) bl many_args
  ; 4) many_args の戻り値は r3 に入っているので、そのまま復帰して return
  ;
  ; 観察ポイント:
  ;   - “引数セットがレジスタへの li 連打” になっていて見通しが良い
  ;   - x86-64 SysV の “6個までレジスタ” と雰囲気が違うことが体感できる

00fe1694 <direct>:
  fe1694:  60 00 00 00    nop
  fe1698:  4e 80 00 20    blr
  ; direct():
  ;   asm volatile("nop");
  ;   nop が 1 命令として残る → return。
  ;
  ; 観察ポイント:
  ;   volatile asm は “消すな” の意味なので、最適化しても残りやすい。

00fe169c <binary>:
  fe169c:  60 00 00 00    nop
  fe16a0:  00 00 00 00    .long 0x0
  fe16a4:  4e 80 00 20    blr
  ; binary():
  ;   asm(".align 4"); asm(".int 0x0");
  ;
  ; ここでは:
  ;   - nop
  ;   - 4バイトの 0 データ（命令ではなく “埋め込みデータ”）
  ;   - return
  ;
  ; 観察ポイント:
  ;   逆アセンブルすると、コードセクションに “命令ではない0” が混ざって見える。
  ;   解析（マルウェア/難読化）で “コードとデータが混在” は頻出なので、この形に慣れると良い。

00fe16a8 <main>:
  fe16a8:  38 60 00 00    li      r3,0
  fe16ac:  4e 80 00 20    blr
  ; main():
  ;   return 0;
  ;   r3=0 → return。
  ;
  ; 観察ポイント:
  ;   PowerPC では戻り値が r3 固定で見えるため、mainも非常に単純になる。
