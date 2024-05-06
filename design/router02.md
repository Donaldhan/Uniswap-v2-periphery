[Uniswap-v2](https://github.com/33357/smartcontract-apps/blob/main/DEX/Uniswap-v2/README.md)



# UniswapV2Library

* UniswapV2Library#quote:在给定数量资产和储备量的情况下， 需要添加的等量的其他资产; A/B = Ra/Rb;
* UniswapV2Library#getAmountOut:根据输入的资产和pair的储备量，获取另外一个资产的最大输出量:(Rout - Rin*Rout/（Rin+inWithoutFee）)= Rout*inWithoutFee/（Rin+inWithoutFee）= Rout*in*997/(1000*Rin+in*997);
* UniswapV2Library#getAmountIn: