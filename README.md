# Item Gamble

Stake an item, pick a target item and let the wheel of fortune decide. Needs Factorio 2.0 with Space Age.

- **Item values:** every item gets a value computed from its recipes, raw materials and how much research it needs. Later items are worth more. Quality and freshness count. Works with items from other mods.
- **Chance:** you always play for more than you put in. The more the target is worth compared to your stake, the lower the chance. The stake only counts with half its value (like buying and selling prices): a 1:1 gamble (same item, same amount) is a coin flip at 50 %, everything more valuable is rarer.
- **Wheel:** an animated reel with near misses, fast and slow spins. The stake is always gone, a win pays the target.
- **Consolation prizes:** some of the losing fields hold small prizes worth about a tenth or a hundredth of the stake.
- **Multiplier:** the green button next to Spin multiplies stake and prize of a spin (x1 up to x100). The chance stays the same.
- **Vanilla controls:** the window shows your inventory, items move with the usual clicks (left, right, shift, ctrl). The stake slot is a supply for many spins.
- **Prize area:** grows with your wins and never keeps empty rows. "Take all" moves everything to your inventory, ctrl click takes one kind.
- **Open it** with ALT + G or the shortcut bar.

All numbers are mod settings: maximum and minimum chance, stake value factor, value per quality level, value for game progress and the share of consolation prizes.

Chat commands: `/gamble-values [search]` writes all item values to `script-output/item-gamble/values.txt`, `/gamble-recalc` (admins) recalculates them.

Languages: English, German.

License: MIT

Source and bug reports: https://github.com/Maxilo92/Item-Gamble
