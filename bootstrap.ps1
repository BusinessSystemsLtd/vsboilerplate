function bootstrap(){
    param(
                [Parameter(Mandatory=$true)][string] $companyName,
                [Parameter(Mandatory=$true)][string] $productName
            )

        if ($companyName -eq $null -or $companyName.Length -eq 0){ throw "Company Name is required"}
        if ($productName -eq $null -or $productName.Length -eq 0){ throw "Product Name is required"}

        $year = (Get-Date).Year
        $copyright = "Copyright © $companyName $year"

        #update shared AssemblyInfo.cs file
        Write-Host "Updating SharedAssemblyInfo"
        $assmemblyInfo = (Get-Content .\SharedAssemblyInfo.cs -Encoding UTF8)
        $assmemblyInfo = $assmemblyInfo.Replace("{COMPANY_NAME}", $companyName)
        $assmemblyInfo = $assmemblyInfo.Replace("{PRODUCT_NAME}", $productName)
        $assmemblyInfo = $assmemblyInfo.Replace("{COPYRIGHT_MESSAGE}", $copyright)
        Set-Content -Path .\SharedAssemblyInfo.cs -Value $assmemblyInfo -Encoding UTF8

        #update StyleCop.Settings file
        Write-Host "Updating StyleCop.Settings"
        $styleCopSettings = (Get-Content .\src\Settings.StyleCop -Encoding UTF8)
        $styleCopSettings = $styleCopSettings.Replace("{COMPANY_NAME}", $companyName)
        Set-Content -Path .\src\Settings.StyleCop -Value $styleCopSettings -Encoding UTF8

        renameAllTheThings $productName $companyName
}

function renameAllTheThings([Parameter(Mandatory=$true)][string] $productName, [Parameter(Mandatory=$true)][string] $companyName){
    $solutionName = $productName.Replace(" ",".")
    $projects = Get-ChildItem -Recurse -Filter *.csproj
    foreach($project in $projects){

        $projectPath = $project.FullName
        $folderPath = $project.Directory.FullName
        $newProjectPath = $project.FullName.Replace("SolutionName", $solutionName)
        $newFolderPath = $project.Directory.FullName.Replace("SolutionName", $solutionName)
        
        Write-Host "Creating Project $newProjectPath"
        Rename-Item $folderPath  $newFolderPath -Force 
        Rename-Item -Path "$newFolderPath\$project" -NewName $newProjectPath -Force  

        $content = Get-Content -Path $newProjectPath
        $content = $content.Replace("SolutionName", $solutionName)
        
        Set-Content -Path $newProjectPath -Value $content -Force 
    }

    Write-Host "Updating Solution File"
    $solution = Get-ChildItem -Filter "*.sln"
    $content = Get-Content -Path $solution.FullName
    $content = $content.Replace("SolutionName", $solutionName)
    Set-Content -Path $solution.FullName -Value $content -Force 
    Rename-Item $solution.FullName $solution.Name.Replace("SolutionName", $solutionName)

    Rename-Item "SolutionName.sln.DotSettings" "$solutionName.sln.DotSettings" 

    $files = Get-ChildItem -Filter *.cs -Recurse
    foreach($file in $files){
        Write-Host "Updating Namespaces"
        $content = Get-Content -Path $file.FullName

        $content = $content.Replace("SolutionName", $solutionName)
        $content = $content.Replace("{COMPANY_NAME}", $companyName)
        Set-Content -Path $file.FullName -Value $content -Force 
    }

    Write-Host "Updateing Rakefile"
    $content = Get-Content -Path "Rakefile.rb"
    $content = $content.Replace("SolutionName.sln", "$solutionName.sln")
    Set-Content -Path "Rakefile.rb" -Value $content
}

bootstrap;