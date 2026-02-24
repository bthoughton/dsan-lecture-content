import torch.nn as nn


class ResidualBlock(nn.Module):
    def __init__(self, in_channels, out_channels, stride = 1):

        self.stride = stride
        
        super(ResidualBlock, self).__init__()
        self.conv1 = nn.Sequential(
                        nn.Conv2d(in_channels, out_channels, kernel_size = 3, stride = stride, padding = 1),
                        nn.BatchNorm2d(out_channels),
                        nn.ReLU()
                        )
        self.conv2 = nn.Sequential(
                        nn.Conv2d(out_channels, out_channels, kernel_size = 3, stride = 1, padding = 1),
                        nn.BatchNorm2d(out_channels)
                    )
        
        # If stride is greater than one the image will be down sampled
        # This if statement should be remove and downsample should always be defined and rely on stride attribute during
        # forward to determine if downsample is needed
        # if stride > 1:
        self.downsample = nn.Sequential(
            nn.Conv2d(in_channels, out_channels, kernel_size=1, stride=stride),
            nn.BatchNorm2d(out_channels)
        )
    
        # else:
        #     self.downsample = False
            
        self.relu = nn.ReLU()
        
    def forward(self, x):

        y = self.conv1(x)
        y = self.conv2(y)

        # Need to update the code to this
        if self.stride > 1:
            residual = self.downsample(x)

        # And remove this
        # if self.downsample:
        #     residual = self.downsample(x)

        else:
            residual = x

        y += residual
        y = self.relu(y)

        return y
    

class ResidualModule(nn.Module):

    def __init__(self, in_channels, out_channels, num_blocks, down_sample=True) -> None:
        super(ResidualModule, self).__init__()

        if down_sample:
            blocks = [ResidualBlock(in_channels, out_channels, stride=2)]
            
        else:
            blocks = [ResidualBlock(in_channels, out_channels, stride=1)]

        for _ in range(num_blocks-1):
            blocks.append(ResidualBlock(out_channels, out_channels))

        self.module = nn.Sequential(*blocks)

    
    def forward(self, x):
        return self.module(x)
    

class ResNet18(nn.Module):

    def __init__(self) -> None:
        super(ResNet18, self).__init__()
        self.layers = nn.Sequential(
            nn.Conv2d(in_channels=3, out_channels=64, kernel_size=7, stride=2, padding=3),
            nn.BatchNorm2d(64),
            nn.MaxPool2d(kernel_size = 3, stride = 2, padding = 1),
            self._build_res_block(),
            nn.AvgPool2d(7, stride=1),
            nn.Flatten()
        )

    def _build_res_block(self):
        in_channels = 64
        out_channels = 128
        modules = [ResidualModule(in_channels, in_channels, num_blocks=2, down_sample=False)]
        for _ in range(3):
            modules.append(ResidualModule(in_channels, out_channels, num_blocks=2))
            in_channels = out_channels
            out_channels *= 2

        return nn.Sequential(*modules)
    
    def forward(self, x):

        return self.layers(x)
    

class ResNet(nn.Module):

    def __init__(self, in_channels, num_blocks) -> None:
        super(ResNet, self).__init__()
        self.layers = nn.Sequential(
            nn.Conv2d(in_channels=in_channels, out_channels=64, kernel_size=7, stride=2, padding=3),
            nn.BatchNorm2d(64),
            nn.MaxPool2d(kernel_size = 3, stride = 2, padding = 1),
            self._build_res_block(num_blocks),
            nn.AvgPool2d(7, stride=1),
            nn.Flatten()
        )

    def _build_res_block(self, num_blocks):
        in_channels = 64
        out_channels = 128
        modules = [ResidualModule(in_channels, in_channels, num_blocks=2, down_sample=False)]
        for _ in range(num_blocks-1):
            modules.append(ResidualModule(in_channels, out_channels, num_blocks=2))
            in_channels = out_channels
            out_channels *= 2

        return nn.Sequential(*modules)
    
    def forward(self, x):

        return self.layers(x)


class InConv(nn.Module):
    def __init__(self, in_channels=1, out_channels=64, max_pool=False):
        super().__init__()

        layers = [
            nn.Conv2d(in_channels=in_channels, out_channels=out_channels, kernel_size=7, stride=2, padding=3),
            nn.BatchNorm2d(64)
        ]

        if max_pool:
            layers.append(nn.MaxPool2d(kernel_size=3, stride=2, padding=1))

        self.layers = nn.Sequential(*layers)
        
    def forward(self, x):
        return self.layers(x)