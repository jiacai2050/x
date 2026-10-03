# 2.4 Tokenizer 与 8:1 内存估算哲学

在传统编译原理课程中，词法分析器（Lexer / Tokenizer）常使用基于正则表达式的状态机生成工具（如 Flex 或 Lex）。这类工具在理论上具备良好的形式化表达能力，但生成的代码常伴随间接查表与分散的分支跳转，且有时会伴随不可预期的临时内存分配。

Zig 0.17 的词法分析器位于 [`lib/std/zig/tokenizer.zig`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/zig/tokenizer.zig)。它的工程目标很明确：**保持机械同构（Mechanical Sympathy）、实现零堆内存分配，以及采用一次性容量预估策略。**

---

## 零分配的流式词法切词器

在 [`lib/std/zig/tokenizer.zig`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/zig/tokenizer.zig) 中，`Tokenizer` 的结构体非常轻量：

```zig
pub const Tokenizer = struct {
    buffer: [:0]const u8,
    index: usize,

    pub fn init(buffer: [:0]const u8) Tokenizer {
        return .{
            .buffer = buffer,
            .index = 0,
        };
    }

    pub fn next(self: *Tokenizer) Token {
        // 无状态的 switch-case 循环扫描
        // ...
    }
};
```

核心特点：
1. `Tokenizer` **不持有任何内存分配器（Allocator）**，在其整个生命周期中不会主动调用堆内存分配。
2. 每次调用 `next()`，它仅在输入文本缓冲区上滑动游标（`index`），并返回一个纯值类型的 `Token`：
   ```zig
   pub const Token = struct {
       tag: Tag,
       loc: Loc,

       pub const Loc = struct {
           start: usize,
           end: usize,
       };
   };
   ```

---

## 8:1 经验内存预分配策略

在将源码文本转换为语法树时，一个常见的性能开销是**动态数组在不断调用 `append` 过程中触发的多次扩容与数据拷贝（Realloc & Copy）**。每次扩容不仅带来内存拷贝开销，还可能导致虚拟内存碎片。

查看 Zig 0.17 在语法解析入口处 [`lib/std/zig/Ast.zig#L153-L165`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/zig/Ast.zig#L153-L165) 的实现：

```zig
pub fn parse(gpa: Allocator, source: [:0]const u8, options: ParseOptions) Allocator.Error!Ast {
    var tokens = Ast.TokenList{};
    defer tokens.deinit(gpa);

    // 统计经验表明：Zig 代码平均每 8 个源码字节对应 1 个 Token
    const estimated_token_count = source.len / 8;
    try tokens.ensureTotalCapacity(gpa, estimated_token_count);

    var tokenizer = std.zig.Tokenizer.init(source);
    while (true) {
        const token = tokenizer.next();
        try tokens.append(gpa, .{
            .tag = token.tag,
            .start = @intCast(token.loc.start),
        });
        if (token.tag == .eof) break;
    }
    // ...
```

### 为什么选择 8:1？
Zig 编译器团队通过对全量标准库与多类开源代码库的实证测量发现：
一段典型的 Zig 代码包含标识符、关键字、标点符号、空格与注释。统计上，**源代码的字节长度与生成的 Token 数量的比值相对稳定在 8:1 左右**。

例如：
- 对于一个 80 KB 的 `.zig` 源码文件，大约包含 10,000 个 Token。
- 解析开始前，编译器直接通过 `source.len / 8`，向分配器**预先申请容纳约 10,000 个 Token 的存储空间**。

这种启发式预估使得绝大多数源文件在词法分析过程中**仅需进行一次连续内存分配**，有效避免了多次动态扩容重分配的开销。

---

## Token 结构本身的紧凑表示

不仅容量预估合理，Token 存入 `Ast.TokenList` 后的结构也经过了精简：

```zig
pub const TokenList = std.MultiArrayList(struct {
    tag: Token.Tag,      // 1 字节枚举
    start: ByteOffset,   // 4 字节整数 (u32，记录源文本中的起始字节偏移)
});
```

每个 Token 仅占用 **5 个字节**。
在词法阶段甚至不需要单独存储 Token 的结束位置（`end`）：当语法分析需要确定 Token 的文本范围时，其结束位置通常直接对应下一个 Token 的 `start`，或根据定长符号的语义规则就地计算得出。

---

## 阶段小结

通过本部分的分析，我们可以看到 Zig 0.17 在前端阶段的底层优化措施：
1. **SoA 数据布局（`MultiArrayList`）**：消除结构体内填充浪费，提高缓存行中有效数据的密度；
2. **零指针平铺 AST**：将基础语法节点统一压缩为 13 字节紧凑结构，辅以 `extra_data` 承载复杂节点；
3. **8:1 经验预分配算法** 与零分配流式扫描，降低了内存动态扩容的频率。

在完成语法树的高效构建后，编译器需要进入更关键的语义分析与中间表示生成阶段。

接下来，第 3 部分将探讨 Zig 编译器的双层中间表示机制——**ZIR 与 AIR**。
