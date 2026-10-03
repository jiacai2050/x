# 1.1 经典编译器的标准阶段

编译器（Compiler）的核心功能是将高级语言源代码（如 C、Zig、Rust）转换为目标平台可以直接执行的机器指令。

从软件实现角度来看，编译器是一条典型的数据转换流水线。本节梳理传统编译器通用的处理阶段与核心概念。

---

## 编译器的“前端-中端-后端-链接”架构

```mermaid
graph LR
    %% Global styles and definitions
    classDef core stroke:#0066cc,stroke-width:2px;
    classDef middle stroke:#ff9900,stroke-width:2px;
    classDef edge stroke:#ccc,stroke-width:2px;
    classDef status stroke:#198754,stroke-width:2px;

    subgraph SG_Stage1["第一阶段: 编译器前端 (Front-End)"]
        direction TB
        Node_Source["源代码文本 (*.zig)"]
        Node_Lexer["词法分析器 (Lexer/Tokenizer)"]
        Node_Parser["语法分析器 (Parser)"]
        Node_AST["抽象语法树 (AST)"]
        Node_Source -- "字符流" --> Node_Lexer
        Node_Lexer -- "标记流 (Tokens)" --> Node_Parser
        Node_Parser -- "构造语法树" --> Node_AST
    end

    subgraph SG_Stage2["第二阶段: 编译器中端 (Middle-End)"]
        direction TB
        Node_Sema["语义分析 (Type Check / Sema)"]
        Node_IR["中间表示 (IR - Intermediate Representation)"]
        Node_Opt["中端代码优化 (Optimization Passes)"]
        Node_Sema -- "类型推断与检查" --> Node_IR
        Node_IR -- "死代码消除/常量折叠" --> Node_Opt
    end

    subgraph SG_Stage3["第三阶段: 编译器后端 (Back-End)"]
        direction TB
        Node_ISel["指令选择 (Instruction Selection)"]
        Node_RegAlloc["寄存器分配 (Register Allocation)"]
        Node_Emit["目标机器码生成 (Obj Code)"]
        Node_ISel -- "选择目标架构指令" --> Node_RegAlloc
        Node_RegAlloc -- "物理寄存器绑定" --> Node_Emit
    end

    subgraph SG_Stage4["第四阶段: 静态链接器 (Linker)"]
        direction TB
        Node_Reloc["符号解析与重定位 (Relocation)"]
        Node_Bin["最终可执行文件 / 动态库"]
        Node_Reloc -- "合并段与布局" --> Node_Bin
    end

    Node_AST -- "输送语法树" --> Node_Sema
    Node_Opt -- "优化后 IR" --> Node_ISel
    Node_Emit -- "输出目标文件 (*.o)" --> Node_Reloc

    style SG_Stage1 stroke:#0066cc,stroke-width:2px;
    style SG_Stage2 stroke:#ff9900,stroke-width:2px;
    style SG_Stage3 stroke:#495057,stroke-width:2px;
    style SG_Stage4 stroke:#198754,stroke-width:2px;

    class Node_Source,Node_AST edge;
    class Node_Lexer,Node_Parser middle;
    class Node_Sema,Node_IR,Node_Opt core;
    class Node_ISel,Node_RegAlloc,Node_Emit edge;
    class Node_Reloc,Node_Bin status;
```

---

## 阶段详解：从字符到机器码

### 1. 词法分析（Lexical Analysis / Tokenization）
- **输入**：纯文本字符串，例如 `const x: u32 = 10 + 20;`。
- **职责**：顺序扫描源文字符，过滤注释与空白符，识别出关键字、标识符、字面量与操作符等独立的语法记号（Token）。
- **输出**：`[Keyword(const), Identifier("x"), Colon, Identifier("u32"), Equal, Number(10), Plus, Number(20), Semicolon]`。

### 2. 语法分析（Syntax Analysis / Parsing）
- **输入**：词法分析生成的 Token 序列。
- **职责**：根据语言文法规则，验证记号序列是否合规，并将其组装为反映层级与结合性的树状结构——**抽象语法树（AST, Abstract Syntax Tree）**。
- **输出**：以加法表达式为例，加法节点作为父节点，左操作数为数字节点 10，右操作数为数字节点 20。

### 3. 语义分析与类型检查（Semantic Analysis / Type Checking）
- **输入**：语法分析生成的 AST。
- **职责**：AST 仅能表达结构合法性，无法证明语义正确。语义分析需要核验：
  1. 标识符是否在有效作用域内声明；
  2. 操作数类型是否匹配，是否存在非法类型隐式转换；
  3. 函数调用参数数量与类型是否与声明一致。
- **输出**：带有类型标注的语法树，或由此转译出的高级中间表示。

### 4. 中间表示与优化（Intermediate Representation & Optimization）
- **职责**：为避免为每一种语言特性针对每一种硬件架构重新实现一遍（$M \times N$ 问题），现代编译器通常先将语法树转为硬件无关的中间表示（IR）。
- **常见形式**：如 LLVM IR 采用的静态单赋值（SSA, Static Single Assignment）形式。在这一阶段，编译器可运行多种平台无关优化：
  - **常量折叠（Constant Folding）**：在编译期直接计算确定结果，如将 `10 + 20` 替换为 `30`；
  - **死代码消除（Dead Code Elimination）**：移除不可达的分支与无副作用的未引用赋值；
  - **函数内联（Inlining）**：将高频小函数展开到调用点，减少调用开销。

### 5. 目标代码生成（Code Generation）
- **职责**：将平台无关的 IR 映射到具体的物理硬件指令集：
  1. **指令选择（Instruction Selection）**：将抽象操作映射为目标架构的具体指令（如 x86 的 `ADD` 或 AArch64 的 `ADD`）；
  2. **寄存器分配（Register Allocation）**：物理通用寄存器数量有限，需要通过图着色或线性扫描算法，将程序中的虚拟变量映射到物理寄存器，超出部分溢出至栈内存。
- **输出**：目标文件（Object File，如 `.o` 或 `.obj`）。

### 6. 链接（Linking）
- **职责**：编译器通常以单个源文件为编译单元生成目标文件。各个目标文件之间对函数或全局变量的交叉引用，需要链接器统一合并段、计算最终物理虚拟地址，并对未定引用进行地址填充（**重定位, Relocation**），最终输出可执行文件或动态库。

---

## 经典架构面临的工程挑战

这一经典流水线在很长一段时间内都是工业界的主流实践。然而，面对现代大型工程数百万行代码的规模、复杂的宏展开、模板泛型实例化与庞大的依赖树，经典模型在实践中暴露出显著的耗时与内存开销问题。下一节将具体分析这些瓶颈。
