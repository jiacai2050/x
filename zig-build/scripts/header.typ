// scripts/header.typ

// 顶层章节（一级标题）排版规则
#show heading.where(level: 1): it => {
  if it.body == [Zig 构建系统指南] {
    // 首页大标题与副标题（作者与制作时间）统一居中对齐
    align(center)[
      #it
      #v(0.5em)
      #text(size: 10pt, fill: rgb("#666666"))[
        作者：jiacai2050 #h(1.5em) 制作时间：BUILD_DATE_PLACEHOLDER
      ]
    ]
    v(1.5em)
  } else {
    pagebreak(weak: true)
    it
  }
}

// 超链接样式区分：使用技术文档经典蓝色高亮
#show link: set text(fill: rgb("#0969da"))
