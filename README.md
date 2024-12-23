# wsl-setup
 
## List of things to setup
1. **How to install a specific version of WSL Ubuntu 22.04 LTS**
    - Open PowerShell as Administrator.
    - Run the command: `wsl --install -d Ubuntu-22.04`.
    - Follow the on-screen instructions to complete the installation.

2. **Update and Upgrade command**
    - Open your WSL terminal.
    - Run the commands:
      ```sh
      sudo apt update
      sudo apt upgrade -y
      ```

3. **Update the Linux system to not ask for a password**
    3. **Update the Linux system to not ask for a password**
        - Open the sudoers file with the command: `sudo visudo`.
        - Add the following line at the end of the file:
          ```sh
          sanjay-dev ALL=(ALL) NOPASSWD:ALL
          ```
        - Save and exit the editor.

4. **Install oh-my-zsh with Autocomplete and other themes**
    - Install `zsh` with the command: `sudo apt install zsh -y`.
    - Make `zsh` your default shell: `chsh -s $(which zsh)`.
    - Install oh-my-zsh: `sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"`.
    - For Autocomplete, install `zsh-autosuggestions`:
      ```sh
      git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
      ```
    - Enable the plugin by adding `zsh-autosuggestions` to the `plugins` array in your `.zshrc` file:
      ```sh
      sed -i 's/plugins=(/plugins=(zsh-autosuggestions /' ~/.zshrc
      ```
    - Restart your terminal or run `source ~/.zshrc`.

5. **Install Miniconda**

    - **Download and Install Mamba**
        - Download the Mamba installer for Linux from the [official github repo](https://github.com/conda-forge/miniforge).
        - Run the installer with the command: `sh Mambaforge-Linux-x86_64.sh`.
        - Follow the on-screen instructions to complete the installation.
        - Initialize Mamba: `mamba init`.
        - Alternatively, you can download Mamba using `curl` or `wget`:
            ```sh
            # Using curl
        ```sh
        curl -L -O "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh"
        bash Miniforge3-$(uname)-$(uname -m).sh
        ```
5. **Install NVIDIA Driver**
     https://docs.nvidia.com/cuda/wsl-user-guide/index.html#cuda-support-for-wsl-2
     - Currently below version works in my sytem
        Driver Version: 538.95       
        CUDA Version: 12.2   

6. **Setup Python environment**
    - Create a new Conda environment: `mamba create --name myenv python=3.12`.
    - Activate the environment: `mamba activate myenv`.
    - Install necessary packages: `mamba install numpy pandas matplotlib`.

7. **Install CUDA Toolkit**
    - Download the CUDA Toolkit from the [official NVIDIA website](https://developer.nvidia.com/cuda-downloads).
    - Follow the installation instructions provided on the website for your specific Linux distribution.
    - Verify the installation by running: `nvcc --version`.

7. **Create a Mamba environment with CUDA GPU support**
    - Ensure you have the NVIDIA drivers installed on your system.
    - Create a new Conda environment with CUDA support: `mamba create -n cuda12-2 python=3.9`.
    - Activate the environment: `mamba activate cuda12-2`.
    - Install necessary packages: `mamba install pytorch torchvision torchaudio pytorch-cuda=12.1 -c pytorch-nightly -c nvidia`.
    
    *Note at the time of install 12.2 version was not avilable, [Pytorch version for cuda 12.2](https://stackoverflow.com/questions/76678846/pytorch-version-for-cuda-12-2) based on this I installed.

    TODO- Setup cuda and install pyturch