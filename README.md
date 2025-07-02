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


## System Monitoring and Troubleshooting

### Running monitor_performance.ps1

If your system feels sluggish or hangs often for no obvious reason, you can use the `monitor_performance.ps1` script to help diagnose performance issues.

**When to Run:**
- When your system is slow, unresponsive, or hangs frequently without any clear reason.

**How to Run:**
1. Open **PowerShell** in **Administrator mode**.
2. Navigate to the directory containing `monitor_performance.ps1`.
3. Execute the script with:
   ```powershell
   .\monitor_performance.ps1
   ```
4. Follow any on-screen instructions provided by the script.

This script will collect and display system performance information to help you identify potential issues.

---

## WSL Disk Cleanup & Reclaiming Space

### 1. Run `wsl_disk_cleanup.sh`

- **Purpose:** Frees up disk space by cleaning up unnecessary files and package caches inside your WSL instance.
- **How to Use:**
  1. Place `wsl_disk_cleanup.sh` in your Linux home directory (or any preferred location).
  2. Make it executable:
     ```sh
     chmod +x wsl_disk_cleanup.sh
     ```
  3. Run the script:
     ```sh
     ./wsl_disk_cleanup.sh
     ```
- **What to Expect:**  
  The script will:
  - Clean up package cache with `sudo apt-get clean`
  - Remove unused packages with `sudo apt-get autoremove`
  - Clean temporary files and logs
  - You will see output messages summarizing freed space and actions taken.

### 2. Reclaim Space Using Optimize-VHD

- **Purpose:** Shrinks the virtual disk file used by WSL2 to reclaim freed space back on your Windows host.
- **How to Use:**
  1. Open **PowerShell as Administrator**.
  2. Run:
     ```powershell
     Optimize-VHD -Path "C:\Users\<username>\AppData\Local\Packages\CanonicalGroupLimited.Ubuntu22.04LTS_79rhkp1fndgsc\LocalState\ext4.vhdx" -Mode Full
     ```
- **What to Expect:**  
  This operation may take several minutes. When finished, the ext4.vhdx file will be smaller if there was unused space to reclaim.

### 3. Finding Your VHDX Path

- Each WSL distribution has its own vhdx file.
- The path generally looks like:
  ```
  C:\Users\<YourUsername>\AppData\Local\Packages\<DistroPackageName>\LocalState\ext4.vhdx
  ```
- **How to Find It:**
  1. List installed WSL distributions:
     ```powershell
     wsl --list --verbose
     ```
  2. Find the folder in:
     ```
     %USERPROFILE%\AppData\Local\Packages
     ```
     Matching your distribution (e.g., contains `Ubuntu22.04LTS`).
  3. The vhdx file is inside that folder’s `LocalState` directory.
