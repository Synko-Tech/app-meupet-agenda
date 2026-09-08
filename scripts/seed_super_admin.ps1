param(
  [string] $ProjectId = "meupet-agenda-app",
  [string] $ApiKey,
  [string] $Email,
  [string] $Password,
  [string] $Name = "Super Admin"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Email)) {
  throw "Parametro -Email e obrigatorio."
}
if ([string]::IsNullOrWhiteSpace($Password)) {
  throw "Parametro -Password e obrigatorio."
}
if ([string]::IsNullOrWhiteSpace($ApiKey)) {
  throw "Parametro -ApiKey e obrigatorio."
}

function Get-FirebaseCliAccessToken {
  $login = firebase.cmd login:list --json | ConvertFrom-Json
  if (-not $login.result -or -not $login.result[0].tokens.access_token) {
    throw "Firebase CLI nao esta autenticado. Rode firebase login antes."
  }
  return $login.result[0].tokens.access_token
}

function Invoke-FirebaseAuthSignup {
  $body = @{
    email = $Email
    password = $Password
    returnSecureToken = $true
  } | ConvertTo-Json

  try {
    return Invoke-RestMethod `
      -Method Post `
      -Uri "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$ApiKey" `
      -ContentType "application/json" `
      -Body $body
  } catch {
    if ($_.Exception.Response) {
      $reader = New-Object System.IO.StreamReader(
        $_.Exception.Response.GetResponseStream()
      )
      $details = $reader.ReadToEnd()
      if ($details -like "*EMAIL_EXISTS*") {
        throw "O usuario $Email ja existe no Firebase Auth. Use o UID existente e atualize o documento users/{uid} para role=super_admin."
      }
      throw "Falha ao criar usuario no Firebase Auth: $details"
    }
    throw
  }
}

function Set-SuperAdminDocument($UserId, $AccessToken) {
  # Perfil semeador conhecido: profileComplete: true evita o bloqueio do gate
  # de perfil (CompleteProfileScreen) para o super admin bootstrap. Nao ha
  # userPrivate (CPF/endereco) — consistente com seeds de teste; usuarios
  # reais completam o perfil pelo app.
  $document = @{
    fields = @{
      nome = @{ stringValue = $Name }
      email = @{ stringValue = $Email }
      telefone = @{ nullValue = $null }
      role = @{ stringValue = "super_admin" }
      tipo_usuario = @{ stringValue = "super_admin" }
      ativo = @{ booleanValue = $true }
      profileComplete = @{ booleanValue = $true }
      schemaVersion = @{ integerValue = 2 }
      createdAt = @{ timestampValue = (Get-Date).ToUniversalTime().ToString("o") }
      updatedAt = @{ timestampValue = (Get-Date).ToUniversalTime().ToString("o") }
    }
  } | ConvertTo-Json -Depth 8

  $headers = @{
    Authorization = "Bearer $AccessToken"
    "Content-Type" = "application/json"
  }

  Invoke-RestMethod `
    -Method Patch `
    -Uri "https://firestore.googleapis.com/v1/projects/$ProjectId/databases/(default)/documents/users/$UserId" `
    -Headers $headers `
    -Body $document | Out-Null
}

$signup = Invoke-FirebaseAuthSignup
$accessToken = Get-FirebaseCliAccessToken
Set-SuperAdminDocument -UserId $signup.localId -AccessToken $accessToken

Write-Output "Super admin criado com sucesso."
Write-Output "Email: $Email"
Write-Output "UID: $($signup.localId)"
