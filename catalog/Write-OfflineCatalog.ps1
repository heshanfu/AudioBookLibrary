[CmdletBinding()]
param (
	[string]$CatalogFile = './book.csv',
	[string]$FilePattern = './release/offline_catalog.json',
	[string]$Separator = ',',
	[string[]]$Locales = @("French") #,"English","Spanish")
)

function Reorder-Text($text) {
	try {
		if ($text.Contains($Separator)) {
			return ($text.Split($Separator)[-1]).Trim() + " " + ($text.Split($Separator)[0]).Trim()
		}
	} catch {

	}
	return $text
}

function Reorder-Name($text) {
	$name = Reorder-Text $text
	if ($text.Contains($Separator)) {
		return ($name + "$Separator " + $text.Split($Separator)[0]).Trim()
	}
	return $name
}
function Get-Tracks($zipfile) {
	# http://www.archive.org/download/fables_lafontaine_01_librivox/fables_lafontaine_01_librivox_64kb_mp3.zip
	$m3u=$zipfile -ireplace "_mp3.zip",".m3u"
	$enc = [System.Text.Encoding]::ASCII
	
	$cacheFile = $m3u
	$cacheFile = $cacheFile -ireplace "http://",""
	$cacheFile = $cacheFile -ireplace "/","|"
	$cacheFile = "./cache/$cacheFile"

	try {
		if (-Not (Test-Path $cacheFile)) {
			$m3uResponse = Invoke-WebRequest -Uri $m3u -UseBasicParsing -OutFile $cacheFile #| Select -ExpandProperty Content
		}

		$m3uContent = Get-Content $cacheFile -Raw
		return $m3uContent.Split("`n")

	} catch { }
	return @()
}

function Get-Cover($zipfile) {
	#https://ia800702.us.archive.org/19/items/fables_lafontaine_01_librivox/fables_lafontaine_01_librivox_files.xml
	return "TODO"
}

Set-Location $PSScriptRoot

$catalog = @()
$allBook = Import-Csv -Path $CatalogFile -Delimiter $Separator

foreach ($locale in $Locales) {
	Write-Host "###### PROCESSING $locale #######"
	$File = $FilePattern -ireplace "catalog","catalog-$locale"
	$part = "Part"
	switch ($locale) {
		"French" { $part = "Partie" }
		Default {}
	}
	$count = 0
	$audioBooks = $allBook | Where language -ieq $locale
	foreach ($book in $audioBooks) {
		$count++
		if ($book -match "^#") {
			Write-Host "$count - Skipping book $($book)." -ForegroundColor Yellow
			continue
		}
		
		$id = $book._id
		try {
			$id = $book.etext.Split("/")[-1]
		} catch {
			Write-Error "Error fetching ETEXT ID"
		}

		Write-Host "$count - Processing $($id).." -ForegroundColor Magenta

		$ebookObject = New-Object psobject -Property @{
			title=''
			image='TODO'
			album=$book.title #(Reorder-Text $book.title)
			artist=(Reorder-Name $book.author)
			genre=$book.category
			source=''
			trackNumber=0
			totalTrackCount=0
			duration=0
			site=$book.etext
		}

		$trackUrls = (Get-Tracks $book.zipfile)
		# Populate tracks
		$trackNumber = 0
		$totalCount = $trackUrls| Measure-Object | Select-Object -Expand Count

		foreach ($t in $trackUrls) {
			Write-Host "`t $t" -ForegroundColor Magenta

			$trackNumber++
			$trackObject = $ebookObject.psobject.Copy()
			$trackObject.title = "$part $trackNumber"
			$trackObject.source = $t
			$trackObject.trackNumber = $trackNumber
			$trackObject.totalTrackCount = $totalCount

			$catalog += $trackObject
			$trackObject
		}
		if ($trackNumber -eq 0) {
			Write-Error "No tracks found for $($ebookObject.album) on $($ebookObject.zipfile)"
		}
	}
	$sortedProperty = ($catalog[0] | Get-Member -Type NoteProperty | Select-Object -Expand Name)

	$sorted = New-object psobject -Property @{music=$catalog}
	$sorted.music = $sorted.music | Sort-Object album,site,trackNumber | Select-Object -Property $sortedProperty
	Set-Content -Path $File -Value ($sorted | ConvertTo-Json) -Force -Encoding UTF8
}