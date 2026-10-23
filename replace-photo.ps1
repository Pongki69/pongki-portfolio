$ErrorActionPreference = 'Stop'

function Invoke-Git {
  param([Parameter(Mandatory = $true)][string[]]$GitArguments)

  & git -C $repoRoot @GitArguments
  if ($LASTEXITCODE -ne 0) {
    throw "Git command failed: git $($GitArguments -join ' ')"
  }
}

$repoRoot = $PSScriptRoot
$photoDirectory = Join-Path $repoRoot 'replace-photo'
$destination = Join-Path $repoRoot 'graduation-photo.png'
$temporaryImage = Join-Path $repoRoot 'graduation-photo-new.png'
$supportedExtensions = @('.jpg', '.jpeg', '.png', '.bmp', '.gif')
$avatarPixelSize = 880

if (-not (Test-Path -LiteralPath (Join-Path $repoRoot '.git'))) {
  throw 'This folder is not a Git repository.'
}
if (-not (Test-Path -LiteralPath $photoDirectory -PathType Container)) {
  throw 'The replace-photo folder is missing.'
}

$photos = @(Get-ChildItem -LiteralPath $photoDirectory -File | Where-Object {
  $supportedExtensions -contains $_.Extension.ToLowerInvariant()
})

if ($photos.Count -ne 1) {
  throw "Put exactly one JPG, JPEG, PNG, BMP, or GIF image in '$photoDirectory', then run this file again. Found $($photos.Count) supported images."
}

$origin = (& git -C $repoRoot remote get-url origin 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($origin -join ''))) {
  throw 'GitHub remote "origin" is not configured for this repository.'
}

$branch = (& git -C $repoRoot branch --show-current 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($branch -join ''))) {
  throw 'Could not identify the current Git branch. Check out a branch and run this file again.'
}

$stagedChanges = (& git -C $repoRoot diff --cached --quiet 2>$null)
if ($LASTEXITCODE -ne 0) {
  throw 'There are already staged Git changes. Commit or unstage them before running this file so it only commits your photo.'
}

Add-Type -AssemblyName System.Drawing
$image = $null
$bitmap = $null
$graphics = $null
try {
  $image = [System.Drawing.Image]::FromFile($photos[0].FullName)
  if ($image.PropertyIdList -contains 0x0112) {
    $orientation = [int]$image.GetPropertyItem(0x0112).Value[0]
    switch ($orientation) {
      2 { $image.RotateFlip([System.Drawing.RotateFlipType]::RotateNoneFlipX) }
      3 { $image.RotateFlip([System.Drawing.RotateFlipType]::Rotate180FlipNone) }
      4 { $image.RotateFlip([System.Drawing.RotateFlipType]::Rotate180FlipX) }
      5 { $image.RotateFlip([System.Drawing.RotateFlipType]::Rotate90FlipX) }
      6 { $image.RotateFlip([System.Drawing.RotateFlipType]::Rotate90FlipNone) }
      7 { $image.RotateFlip([System.Drawing.RotateFlipType]::Rotate270FlipX) }
      8 { $image.RotateFlip([System.Drawing.RotateFlipType]::Rotate270FlipNone) }
    }
  }
  $cropSize = [Math]::Min($image.Width, $image.Height)
  $cropX = [int][Math]::Floor(($image.Width - $cropSize) / 2)
  $cropY = [int][Math]::Floor(($image.Height - $cropSize) / 2)
  $sourceBounds = [System.Drawing.Rectangle]::new($cropX, $cropY, $cropSize, $cropSize)
  $targetBounds = [System.Drawing.Rectangle]::new(0, 0, $avatarPixelSize, $avatarPixelSize)
  $bitmap = [System.Drawing.Bitmap]::new($avatarPixelSize, $avatarPixelSize, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $graphics.DrawImage($image, $targetBounds, $sourceBounds, [System.Drawing.GraphicsUnit]::Pixel)
  $bitmap.Save($temporaryImage, [System.Drawing.Imaging.ImageFormat]::Png)
}
finally {
  if ($graphics) { $graphics.Dispose() }
  if ($bitmap) { $bitmap.Dispose() }
  if ($image) { $image.Dispose() }
}

Move-Item -LiteralPath $temporaryImage -Destination $destination -Force
Invoke-Git -GitArguments @('add', '--', 'graduation-photo.png')

& git -C $repoRoot diff --cached --quiet -- graduation-photo.png
if ($LASTEXITCODE -eq 1) {
  Invoke-Git -GitArguments @('commit', '-m', 'Update portfolio profile photo')
} elseif ($LASTEXITCODE -ne 0) {
  throw 'Could not check the staged photo change.'
} else {
  Write-Host 'The selected image is already the current portfolio photo; no new commit is needed.'
}

Invoke-Git -GitArguments @('push', 'origin', $branch)
Write-Host "Published '$($photos[0].Name)' to GitHub on branch '$branch'."
