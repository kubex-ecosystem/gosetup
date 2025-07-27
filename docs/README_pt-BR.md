# **GoSetup 🐹 ⚡ - Instalador Inteligente para Go**

🚀 **Instale e configure Golang de forma rápida e sem complicações** em **Linux**, **Mac** e **Windows**!

[![Contributions Welcome](https://img.shields.io/badge/contributions-welcome-brightgreen.svg?style=flat)](https://github.com/rafa-mori/gosetup)
[![CI Status](https://github.com/rafa-mori/gosetup/actions/workflows/test.yml/badge.svg)](https://github.com/rafa-mori/gosetup/actions/workflows/test.yml)

---

## 🚀 **Instalação Rápida**
### 🏎️ **Método Instantâneo (wget/curl)**
```bash
wget https://raw.githubusercontent.com/rafa-mori/gosetup/refs/heads/main/go.sh && bash gosetup.sh
```
```bash
bash <(curl -sL https://git.io/gosetup)
```

### 🛠️ **Clonando e executando manualmente**
```bash
git clone https://github.com/rafa-mori/gosetup.git
cd gosetup
bash go.sh
```

> 💡 **Dica:** O script instala Go em `$HOME/.go` e configura `$HOME/go` como workspace.  
> Para personalizar esses diretórios, defina `GOROOT` e `GOPATH` antes da instalação:
```bash
export GOROOT=/opt/go
export GOPATH=$HOME/projects/go
```

---

## 🎯 **Recursos**
✅ **Instalação e atualização automáticas**  
✅ **Definição de versão específica do Go**  
✅ **Compatível com Windows, Linux e macOS**  
✅ **Configuração de ambiente inteligente**  
✅ **Suporte a múltiplas arquiteturas (ARM, AMD64, i386)**  
✅ **Integração perfeita com workflows do GitHub Actions**  

---

## 🛠️ **Comandos Essenciais**
### 🔹 **Instalar ou atualizar Go**
```bash
bash go.sh install
```
```powershell
.\go.ps1 -Command install
```

### 🔹 **Definir uma versão específica**
```bash
bash go.sh install --version 1.19.4
```
```powershell
.\go.ps1 -Command install -Version 1.19.2
```

### 🔹 **Verificar se uma versão já está instalada**
```bash
bash go.sh check --version 1.19.4
```
```powershell
.\go.ps1 -Command check -Version 1.19.2
```

### 🔹 **Desinstalar Go**
```bash
bash go.sh remove
```
```powershell
.\go.ps1 -Command remove
```

### 🔹 **Exibir menu de ajuda**
```bash
bash go.sh help
```
```powershell
.\go.ps1 -Command help
```

---

## 🐳 **Rodando Testes com Docker**
Evite interferências no sistema e garanta um ambiente consistente:
```bash
make test
```
```powershell
.\go.ps1 -Command test
```

---

## 💡 **Contribua para o Projeto**
1. ⭐ **Dê uma estrela no repositório** e ajude a fortalecer o projeto!  
2. 🔄 **Faça um fork** e clone o repositório.  
3. 🛠️ **Crie uma nova branch** e implemente suas mudanças.  
4. 📌 **Envie um pull request** e aguarde revisão.  
5. 🎉 **Junte-se à comunidade e acompanhe as novidades!**  

---

## 🔍 **Como Funciona**
O script executa os seguintes passos:
1️⃣ **Detecta** sistema operacional e arquitetura.  
2️⃣ **Verifica** a versão disponível do Go.  
3️⃣ **Baixa e instala** a versão correta.  
4️⃣ **Cria e configura** os diretórios (`GOROOT`, `GOPATH`).  
5️⃣ **Adiciona ao PATH** automaticamente.  
6️⃣ **Limpa** arquivos desnecessários para manter eficiência.  

---

## 🛠️ **Usando em CI/CD com GitHub Actions**
Automatize a instalação do Go na versão especificada no `go.mod`:

```yaml
- name: Install Go (Exact version from go.mod)
  run: |
    export NON_INTERACTIVE=true
    bash -c "$(curl -sSfL 'https://raw.githubusercontent.com/rafa-mori/gosetup/main/go.sh')" -s --version "$(grep '^go ' go.mod | awk '{print $2}')"
```

---

<p align="center">🚀 **Simples. Eficiente. Poderoso.** 🔥</p>
