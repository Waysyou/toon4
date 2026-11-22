# toon4 中文快速上手

下面三组样例演示如何比较 JSON 和 TOON、来回转换，以及定位格式错误。安装 MoonBit 工具链后，在 toon4 仓库根目录运行这些命令。

## 1. 转换商品清单

[商品清单](inventory.json)里的六条记录有相同字段，适合把字段名统一写在表头。在把清单交给模型之前，先比较两种格式的大小。

```sh
moon run --target native cmd/toon4 -- analyze examples/cli_walkthrough/inventory.json
```

这份样例的紧凑 JSON 为 599 字节、约 165 token，逗号分隔的 TOON 为 217 字节、约 95 token。报告显示 `RECOMMEND_TOON`，估算输入 token 减少 42.4%。实际 token 数取决于模型的分词器。

接着转换成 TOON，再转回 JSON。两条命令会把输出保存到当前目录。

```sh
moon run --target native cmd/toon4 -- encode -o inventory.toon examples/cli_walkthrough/inventory.json
moon run --target native cmd/toon4 -- decode -o inventory-restored.json inventory.toon
```

打开 `inventory.toon` 能看到一行表头和六行商品数据。`inventory-restored.json` 恢复了原清单的商品记录，可以继续交给读取 JSON 的程序。

## 2. 判断复杂订单要不要转换

[订单样例](orders.json)里的订单包含不同的字段，有的记录发货信息，有的记录优惠或退款。

```sh
moon run --target native cmd/toon4 -- analyze examples/cli_walkthrough/orders.json
```

报告会指出 `orders` 的字段不一致，因此使用普通列表。逗号分隔的 TOON 约 140 token，紧凑 JSON 约 100 token。这份样例的建议是 `KEEP_COMPACT_JSON`，即继续使用紧凑 JSON。

## 3. 找到写错的 TOON 行

[错误样例](inventory-invalid.toon)里的表头有三列，鼠标那一行少写了库存数量。

```sh
moon run --target native cmd/toon4 -- check examples/cli_walkthrough/inventory-invalid.toon
```

预期结果是退出码 `1`，并显示第 3 行、第 3 列及错误原因。

```text
DecodeError[E_WIDTH] at line 3, column 3: expected 3 tabular row values, but got 2
  3 |   MS-02,SZ
    |   ^^^^^^^^
```

要运行项目的测试，在仓库根目录执行 `moon test --target native`。
