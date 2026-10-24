// common/mdbook/header.typ

// 顶层章节（一级标题）排版规则：
// 自动检测整篇文档的第一个一级标题作为首页大标题居中展示，后续各章一级标题自动分页
#show heading.where(level: 1): it => {
  let is-first = (it == query(heading.where(level: 1)).first())
  if is-first {
    align(center)[
      #it
      #v(0.5em)
      #text(size: 10pt, fill: rgb("#666666"))[
        BOOK_META_SUBTITLE_PLACEHOLDER
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
