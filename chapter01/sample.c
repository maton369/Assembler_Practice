/*
 * このファイルは「C→アセンブラ」観察用の教材セットである。
 * 目的は、コンパイラが生成するアセンブラ（ABI/命令選択/最適化の癖）を
 * 小さな関数単位で確実に観測できるようにすることにある。
 *
 * 想定（説明の基準）:
 *   x86-64 System V ABI（Linux/macOS系）
 *     - 引数(整数/ポインタ) : RDI, RSI, RDX, RCX, R8, R9
 *     - 戻り値(整数/ポインタ): RAX
 *     - 32bit戻り値(int)は EAX を書く（EAX書き込みはRAX上位32bitをゼロ化する）
 *
 * 注意:
 *   - 実際の生成アセンブラは「最適化レベル(-O0/-O2)」「コンパイラ(GCC/Clang)」
 *     「ターゲットABI(Linux SysV / Windows x64 / x86 32bit)」で変わる。
 *   - ただし“何が観察ポイントか”は同じである。以下のコメントはその観察ポイントを説明する。
 */

/* ----------------------------
 * 0) 何もしない関数
 * ---------------------------- */
void null()
{
  /*
   * 典型的な生成イメージ:
   *   ret
   *
   * -O0 だとデバッグ用にフレームを作る場合がある:
   *   push rbp
   *   mov  rbp, rsp
   *   pop  rbp
   *   ret
   *
   * 観察ポイント:
   *   「何もしない関数」は最適化が効くとほぼ ret だけになる。
   */
  return;
}

/* ----------------------------
 * 1) 定数を返す
 * ---------------------------- */
int return_zero()
{
  /*
   * 典型:
   *   xor eax, eax   ; EAX=0 (短くて速い定番)
   *   ret
   *
   * 観察ポイント:
   *   EAX に書くと RAX 上位32bitがゼロになる（x86-64の仕様）。
   */
  return 0;
}

int return_one()
{
  /*
   * 典型:
   *   mov eax, 1
   *   ret
   */
  return 1;
}

/* ----------------------------
 * 2) sizeof を返す（コンパイル時定数）
 * ---------------------------- */
int return_int_size()
{
  /*
   * sizeof は「実行時に計算しない」= コンパイル時定数。
   * 典型:
   *   mov eax, 4
   *   ret
   *
   * 観察ポイント:
   *   sizeof 由来の関数は“即値ロード”だけになりやすい。
   */
  return sizeof(int);
}

int return_pointer_size()
{
  /*
   * x86-64なら 8、x86(32bit)なら 4。
   * 典型:
   *   mov eax, 8
   *   ret
   *
   * 観察ポイント:
   *   ポインタ幅がABIに依存することを実感できる。
   */
  return sizeof(int *);
}

int return_short_size()
{
  /*
   * 典型:
   *   mov eax, 2
   *   ret
   */
  return sizeof(short);
}

int return_long_size()
{
  /*
   * longは環境差が大きい:
   *   - LP64(Linux/macOS x86-64): long=8
   *   - LLP64(Windows x64):      long=4
   *
   * 観察ポイント:
   *   同じソースでもターゲットABIで値が変わる（=生成アセンブラも変わる）。
   */
  return sizeof(long);
}

/* ----------------------------
 * 3) short/long の即値を返す（符号・拡張の癖）
 * ---------------------------- */
short return_short()
{
  /*
   * 0x7788 は16bit範囲。
   * 典型:
   *   mov eax, 0x7788   ; 下位16bit(AX)に値が入る
   *   ret
   *
   * 観察ポイント:
   *   short戻り値は “AX(=RAX下位16bit)” を使う。
   *   呼び出し側で int に昇格する場合、ゼロ拡張/符号拡張がどこで起きるかを見るとよい。
   */
  return 0x7788;
}

long return_long()
{
  /*
   * 0x778899aa は32bit範囲の定数。
   * x86-64(LP64)で long=8 の場合でも、コンパイラはよく
   *   mov eax, 0x778899aa
   * を使う（EAX書き込みで上位32bitがゼロ化するため）。
   *
   * 観察ポイント:
   *   「32bit即値をmov eaxで入れる」最適化パターン。
   */
  return 0x778899aa;
}

short return_short_upper()
{
  /*
   * 0xffee は16bitで最上位ビットが1なので signed short だと負値。
   *
   * 典型:
   *   mov eax, 0xffee   ; AX=0xffee
   *   ret
   *
   * 観察ポイント:
   *   “返すだけ”なら符号拡張は必ずしも起きない。
   *   どこで符号拡張されるかは「呼び出し側がどう使うか」で決まる。
   */
  return 0xffee;
}

long return_long_upper()
{
  /*
   * 0xffeeddcc は32bitでは符号付きだと負。
   *
   * 重要な観察ポイント（x86-64で long=8 のとき）:
   *   mov eax, 0xffeeddcc をすると
   *     RAX = 0x00000000ffeeddcc  （上位はゼロ）
   * になる。つまり “符号拡張されない”。
   *
   * もし「符号付き long」として 0xffffffffffffddcc のようにしたいなら、
   * 例えば (long)(int)0xffeeddcc のような書き方をして
   * コンパイラに符号拡張の意図を示す必要がある。
   *
   * 観察ポイント:
   *   “EAXに書くと上位がゼロ”という仕様が、符号の意味を変えてしまう場面がある。
   */
  return 0xffeeddcc;
}

/* ----------------------------
 * 4) 引数を返す / 引数位置を見る
 * ---------------------------- */
int return_arg1(int a)
{
  /*
   * SysV ABI では第1引数 a は EDI に入ってくる。
   * 典型:
   *   mov eax, edi
   *   ret
   *
   * 観察ポイント:
   *   引数レジスタ→戻り値レジスタへの単純コピー。
   */
  return a;
}

int return_arg2(int a, int b)
{
  /*
   * 第1引数 a: EDI
   * 第2引数 b: ESI
   *
   * 典型:
   *   mov eax, esi
   *   ret
   *
   * 観察ポイント:
   *   「第2引数はESI」など、ABIの引数順を体に入れる用途。
   */
  return b;
}

/* ----------------------------
 * 5) 加算・定数加算・インクリメント
 * ---------------------------- */
int add(int a, int b)
{
  /*
   * 典型:
   *   lea eax, [rdi + rsi]   ; int計算ならEDI/ESIを使う
   *   ret
   * あるいは:
   *   mov eax, edi
   *   add eax, esi
   *   ret
   *
   * 観察ポイント:
   *   lea はアドレス計算命令だが、加算にも多用される（フラグを変えない等の利点）。
   */
  return a + b;
}

int add3(int a, int b, int c)
{
  /*
   * 第3引数 c は EDX。
   * 典型:
   *   mov eax, edi
   *   add eax, esi
   *   add eax, edx
   *   ret
   *
   * 観察ポイント:
   *   引数が増えると「どのレジスタに入るか」が確認できる。
   */
  return a + b + c;
}

int add_two(int a)
{
  /*
   * 典型:
   *   lea eax, [rdi + 2]   ; または add edi,2 → mov eax,edi
   *   ret
   *
   * 観察ポイント:
   *   定数加算は lea 1発にまとめられることが多い。
   */
  return a + 2;
}

int inc(int a)
{
  /*
   * ++a は「前置インクリメント」だが、この関数では戻り値しか見ないので
   * 実質 a+1 と同等。
   *
   * 典型:
   *   lea eax, [rdi + 1]
   *   ret
   *
   * 観察ポイント:
   *   C上の ++ と +1 の違いは“副作用の見え方”に依存する。
   *   ここでは副作用（元の変数更新）が外に出ないので同じになる。
   */
  return ++a;
}

/* ----------------------------
 * 6) ビット演算 OR
 * ---------------------------- */
int or(int a, int b)
{
  /*
   * 典型:
   *   mov eax, edi
   *   or  eax, esi
   *   ret
   *
   * 観察ポイント:
   *   OR はフラグ更新も行うため、後続の分岐最適化に影響することがある。
   */
  return a | b;
}

int or_one(int a)
{
  /*
   * 典型:
   *   mov eax, edi
   *   or  eax, 1
   *   ret
   *
   * 観察ポイント:
   *   即値ORで下位ビットを立てる典型パターン。
   */
  return a | 1;
}

/* ----------------------------
 * 7) volatile load/store（最適化させないメモリアクセス）
 * ---------------------------- */
int load(volatile int *p)
{
  /*
   * volatile の意味:
   *   コンパイラに「このメモリは外部要因で変わる/副作用がある」ことを伝える。
   *   → 参照を消したり、レジスタにキャッシュしたりしにくくなる。
   *
   * ABI: p は RDI に入る（ポインタ）。
   * 典型:
   *   mov eax, DWORD PTR [rdi]
   *   ret
   *
   * 観察ポイント:
   *   -O2 でも load が消えないことを確認する。
   */
  return *p;
}

void store(volatile int *p)
{
  /*
   * 典型:
   *   mov DWORD PTR [rdi], 0xff
   *   ret
   *
   * 観察ポイント:
   *   即値ストアが必ず残る（volatile）。
   */
  *p = 0xff;
}

long load_long(volatile long *p)
{
  /*
   * long 幅依存:
   *   long=8 なら QWORD load:
   *     mov rax, QWORD PTR [rdi]
   *   long=4 なら DWORD load:
   *     mov eax, DWORD PTR [rdi]
   *
   * 観察ポイント:
   *   long の型幅が命令幅に直結する。
   */
  return *p;
}

void store_long(volatile long *p)
{
  /*
   * long=8 なら 0x11223344 を 64bitに拡張して格納する（上位0）。
   * 典型:
   *   mov QWORD PTR [rdi], 0x11223344   ; 実際には分割されることもある
   *
   * 観察ポイント:
   *   即値の大きさ・命令エンコード都合で、
   *   コンパイラが「一旦レジスタに入れてからストア」する形になることもある。
   */
  *p = 0x11223344;
}

/* ----------------------------
 * 8) 構造体メンバアクセス（オフセット）
 * ---------------------------- */
struct structure {
  int a;  /* offset 0 */
  int b;  /* offset 4 */
  int c;  /* offset 8 */
};

int member(struct structure *p)
{
  /*
   * p は RDI。
   *
   * p->b = 1 は:
   *   mov DWORD PTR [rdi + 4], 1
   *
   * return p->c は:
   *   mov eax, DWORD PTR [rdi + 8]
   *   ret
   *
   * 観察ポイント:
   *   - 構造体は「ベースアドレス + オフセット」の単純なメモリアクセスに落ちる
   *   - パディングが入る構造だとオフセットが変わる（今回の並びは綺麗に 0,4,8）。
   */
  p->b = 1;
  return p->c;
}

/* ----------------------------
 * 9) 静的領域（グローバル変数）へのアクセス
 * ---------------------------- */
int static_value = 10;
long static_long = 0x12345678;

int *get_static_value_addr()
{
  /*
   * グローバルのアドレス取得。
   * x86-64ではRIP相対アドレスをよく使う（位置独立コード: PIC/PIE）。
   * 典型（AT&Tなら）:
   *   lea rax, [rip + static_value]
   *   ret
   *
   * 観察ポイント:
   *   “絶対アドレス”ではなく RIP相対になっていることが多い。
   */
  return &static_value;
}

int get_static_value()
{
  /*
   * 典型:
   *   mov eax, DWORD PTR [rip + static_value]
   *   ret
   *
   * 観察ポイント:
   *   グローバルロードもメモリアクセスとして見える。
   */
  return static_value;
}

void set_static_value(int a)
{
  /*
   * a は EDI。
   * 典型:
   *   mov DWORD PTR [rip + static_value], edi
   *   ret
   */
  static_value = a;
}

/* ----------------------------
 * 10) スタックを使わせる（unused + volatile）
 * ---------------------------- */
#define UNUSED __attribute__((unused))

void set_stack()
{
  /*
   * ここは「スタックにローカル変数を置く」ことを観察させる狙い。
   *
   * volatile により:
   *   - 変数 a/b をレジスタに最適化して消すことが難しくなる
   * UNUSED により:
   *   - “未使用警告”を抑える（コンパイラが消せるかとは別問題）
   *
   * -O0 だと典型:
   *   sub rsp, N
   *   mov DWORD PTR [rsp+off_a], 0xfe
   *   mov DWORD PTR [rsp+off_b], 0xff
   *   add rsp, N
   *   ret
   *
   * 観察ポイント:
   *   「volatileなローカル」はスタックにspillされやすく、ストア命令が残る。
   */
  UNUSED volatile int a = 0xfe;
  UNUSED volatile int b = 0xff;
}

int use_stack()
{
  /*
   * set_stack と似ているが、こちらは a+b を返すため load も発生する。
   * -O0 だと:
   *   mov [rsp+off_a], 0xfe
   *   mov [rsp+off_b], 0xff
   *   mov eax, [rsp+off_a]
   *   add eax, [rsp+off_b]
   *   ret
   *
   * 観察ポイント:
   *   volatile だと “一旦メモリに置いて、そこから読む” が起きやすい。
   */
  volatile int a = 0xfe;
  volatile int b = 0xff;
  return a + b;
}

/* ----------------------------
 * 11) 自己再帰（危険: 実行するとスタック枯渇）
 * ---------------------------- */
void call_self()
{
  /*
   * 典型:
   *   call call_self
   *   ret
   *
   * 観察ポイント:
   *   関数呼び出しは return address をスタックに積む。
   *   無限再帰は必ずスタックオーバーフローで落ちる。
   */
  call_self();
}

/* ----------------------------
 * 12) 関数呼び出し（単純/複合）
 * ---------------------------- */
int call_simple(int a)
{
  /*
   * return_arg1(a) を呼んで返すだけ。
   * ABI的には a は EDI で受け取って、そのまま呼び出し先へ渡せる。
   *
   * 最適化が強いと「インライン化」されて
   *   return a;
   * 相当に潰れることもある（観察するなら -fno-inline や -O0 も検討）。
   *
   * 観察ポイント:
   *   call 命令と、引数がレジスタで受け渡される様子。
   */
  return return_arg1(a);
}

int call_complex1()
{
  /*
   * return_arg1(0xfe) + 1
   *
   * 典型:
   *   mov edi, 0xfe
   *   call return_arg1
   *   add eax, 1
   *   ret
   *
   * 観察ポイント:
   *   - “即値引数を渡す”ために EDI にセットする
   *   - 戻り値 EAX をそのまま演算に使う
   */
  return return_arg1(0xfe) + 1;
}

int call_complex2(int a, int b)
{
  /*
   * static_value = return_arg1(b);
   * return b;
   *
   * b は ESI。return_arg1 は第1引数を EDI に要求するので、
   *   mov edi, esi
   * のように移し替えてから call する。
   *
   * 典型:
   *   mov edi, esi
   *   call return_arg1
   *   mov [rip+static_value], eax
   *   mov eax, esi
   *   ret
   *
   * 観察ポイント:
   *   - 引数レジスタの“付け替え”が発生する
   *   - グローバルストアと戻り値設定が分かれて見える
   */
  static_value = return_arg1(b);
  return b;
}

void call_pointer(int (*f)(void))
{
  /*
   * 関数ポインタ呼び出し（間接call）。
   * f は RDI（ポインタ）。
   *
   * 典型:
   *   call rdi   （AT&Tなら call *%rdi）
   *   ret
   *
   * 観察ポイント:
   *   直接 call label ではなく “call *reg/mem” になる。
   *   CTF/解析で頻出の「間接呼び出し」形。
   */
  f();
}

/* ----------------------------
 * 13) 条件分岐（if）
 * ---------------------------- */
int condition(int a, int b)
{
  /*
   * if (a == b) b = 1;
   * return b + 1;
   *
   * 典型（分岐型）:
   *   cmp edi, esi
   *   jne .Lskip
   *   mov esi, 1
   * .Lskip:
   *   lea eax, [rsi + 1]
   *   ret
   *
   * あるいは（最適化で分岐を減らす）cmov を使うこともある:
   *   cmp edi, esi
   *   mov edx, 1
   *   cmove esi, edx
   *   lea eax, [rsi + 1]
   *   ret
   *
   * 観察ポイント:
   *   - cmp + jcc（条件ジャンプ）の基本形
   *   - cmov（条件付きmove）による分岐削減パターン
   */
  if (a == b)
    b = 1;
  return b + 1;
}

/* ----------------------------
 * 14) ループ（for）
 * ---------------------------- */
int loop(int n)
{
  /*
   * sum = 0; for(i=0;i<n;i++) sum+=i;
   *
   * 典型（素直な形）:
   *   xor eax, eax      ; sum=0
   *   xor ecx, ecx      ; i=0
   * .Lloop:
   *   cmp ecx, edi      ; i vs n
   *   jge .Lend
   *   add eax, ecx      ; sum += i
   *   inc ecx           ; i++
   *   jmp .Lloop
   * .Lend:
   *   ret
   *
   * 観察ポイント:
   *   - ループの骨格は「比較→条件ジャンプ→本体→更新→無条件ジャンプ」
   *   - n<=0 のとき即終了する分岐がどう出るか
   */
  int i, sum = 0;
  for (i = 0; i < n; i++)
    sum += i;
  return sum;
}

/* ----------------------------
 * 15) 引数が多い（レジスタを超えるとスタック渡し）
 * ---------------------------- */
int many_args(int a0, int a1, int a2, int a3,
              int a4, int a5, int a6, int a7)
{
  /*
   * SysV ABIでは第1..6引数はレジスタ、7個目以降はスタックで渡される。
   *   a0: EDI
   *   a1: ESI
   *   a2: EDX
   *   a3: ECX
   *   a4: R8D
   *   a5: R9D
   *   a6: [rsp + ...]   (呼び出し側がpush/ストアして渡す)
   *   a7: [rsp + ...]
   *
   * return a0 + a3 + a5 + a7;
   *
   * 典型:
   *   mov eax, edi
   *   add eax, ecx
   *   add eax, r9d
   *   add eax, DWORD PTR [rsp + off_a7]
   *   ret
   *
   * 観察ポイント:
   *   - レジスタ引数とスタック引数が混ざる
   *   - スタック上のオフセットが「呼び出し規約」と「プロローグ」に依存して変化する
   */
  return a0 + a3 + a5 + a7;
}

int call_many_args()
{
  /*
   * many_args(0,1,2,3,4,5,6,7) を呼ぶ。
   *
   * 典型:
   *   mov edi,0
   *   mov esi,1
   *   mov edx,2
   *   mov ecx,3
   *   mov r8d,4
   *   mov r9d,5
   *   push 7 / mov [rsp+..],7  （a7）
   *   push 6 / mov [rsp+..],6  （a6）
   *   call many_args
   *   add rsp, 16               （積んだ分を戻す）
   *   ret
   *
   * 観察ポイント:
   *   - 7個目以降の引数が「スタックに積まれてからcall」される様子
   *   - スタックアラインメント(16byte)維持のために調整が入ることがある
   */
  return many_args(0, 1, 2, 3, 4, 5, 6, 7);
}

/* ----------------------------
 * 16) インラインasm（直書き命令・データ埋め込み）
 * ---------------------------- */
#ifndef NO_DIRECT
void direct()
{
  /*
   * asm volatile("nop");
   *
   * nop は「何もしない」命令だが、volatile を付けると
   * “消すな”という強い制約になる。
   *
   * 典型:
   *   nop
   *   ret
   *
   * 観察ポイント:
   *   - Cの最適化を超えて命令を残せる
   *   - “副作用”として扱われる（順序も保たれやすい）
   */
  asm volatile ("nop");
  return;
}
#endif

#ifndef NO_BINARY
void binary()
{
  /*
   * asm volatile(".align 4");
   * asm volatile(".int 0x0");
   *
   * .align 4 はアセンブラ指示で、次の配置を 2^4=16 byte 境界に揃えることが多い（as流儀）。
   * .int 0x0 は 4バイトの 0 をバイナリとして埋め込む。
   *
   * 観察ポイント:
   *   - 命令ではなく「セクションに生データを埋める」挙動
   *   - 逆アセンブル時に “コードに見える0” や “謎のデータ” として現れることがある
   */
  asm volatile (".align 4");
  asm volatile (".int 0x0");
  return;
}
#endif

/* ----------------------------
 * 17) main
 * ---------------------------- */
int main()
{
  /*
   * 典型:
   *   xor eax,eax
   *   ret
   *
   * 観察ポイント:
   *   実行ファイルのエントリポイントは _start → libc_start_main → main
   *   のように繋がる（通常）。この main 自体は単に 0 を返すだけ。
   */
  return 0;
}
