begin
  require 'bundler/setup'
  require 'rake'
rescue LoadError
  puts 'Bundler and all the gems need to be installed prior to running this rake script. Installing...'
  system("gem install bundler --source http://rubygems.org")
  sh 'bundle install'
  system("bundle exec rake", *ARGV)
  exit 0
end

gem 'albacore','~> 1.0.rc'
require 'albacore'
require 'fileutils'
require 'rake/clean'
require 'nokogiri'


SLN_DIR = Dir.pwd
CONFIGURATION = ENV['configuration'] || 'Release'
SRC_DIR = "#{SLN_DIR}/src/"
TEST_DIR = "#{SLN_DIR}/test/"
OUTPUT = "build"
SHARED_ASSEMBLY_INFO = "SharedAssemblyInfo.cs"
SOLUTION_FILE = "#{SLN_DIR}/SolutionName.sln"
PACKAGES_DIR = "#{SLN_DIR}/packages"
XUNIT_RUNNER = "#{PACKAGES_DIR}/xunit.runners.1.9.2/tools/xunit.console.clr4.exe"
NUGET_EXE = "#{SLN_DIR}/.nuget/NuGet.exe"

UNIT_TESTS = FileList["#{TEST_DIR}/*/*.csproj"]
OCTOPACK = [] #Project Names for Octopack


Albacore.configure do |config|
  config.log_level = :info  
  config.msbuild.use :net4
end

@xUnitRunnerFullPath = Pathname.new(XUNIT_RUNNER)
@testResultFullPath = Pathname.new(File.join(OUTPUT, "tests"))
@dotCoverFullPath = Pathname.new("../../tools/dotCover/dotCover.exe").realpath if ENV["BUILD_NUMBER"]

#add folders that should be cleaned as part of the clean task
CLEAN.include(OUTPUT)
CLEAN.include(FileList["#{SRC_DIR}}/**/bin/"])
CLEAN.include(FileList["#{SRC_DIR}}/**/obj/"])
CLEAN.include(FileList["#{TEST_DIR}}/**/bin/"])
CLEAN.include(FileList["#{TEST_DIR}}/**/obj/"])

CLOBBER.include(PACKAGES_DIR)

desc "Execute default tasks"
task :default => [ :vars, :restore, :build, :test ]

task :ci_build => [ :clean, :restore, :build, :coverage]

desc 'Print all variables'
task :vars do
  puts "SLN_DIR:              #{SLN_DIR}"
  puts "CONFIGURATION:        #{CONFIGURATION}"
  puts "SRC_DIR:              #{SRC_DIR}"
  puts "TEST_DIR:             #{TEST_DIR}"
  puts "OUTPUT:               #{OUTPUT}"
  puts "SHARED_ASSEMBLY_INFO: #{SHARED_ASSEMBLY_INFO}"
  puts "SOLUTION_FILE:        #{SOLUTION_FILE}"
  puts "XUNIT_RUNNER:         #{XUNIT_RUNNER}"
  puts "NUGET_EXE:            #{NUGET_EXE}"
  puts "UNIT_TESTS:"
  puts UNIT_TESTS.map {|x| " " + x}
  puts "OCTOPACK:"
  puts OCTOPACK.map {|x| " " + x}
end


desc 'Restores NuGet packages'
task :restore  do
  FileList["#{SLN_DIR}/**/packages.config"].push("#{SLN_DIR}/.nuget/packages.config").each { |filepath|
    sh "#{NUGET_EXE} i #{filepath} -o #{PACKAGES_DIR}"
  }
end

desc 'Build the solution'
msbuild :build => [:verify_stylecop_msbuild] do |msb|

  if not File.directory? OUTPUT
    mkpath(OUTPUT)
  end

  msb.verbosity = :normal
  msb.solution = "#{SOLUTION_FILE}"
  msb.targets = [:Clean, :Build]
  msb.nologo

  ignore_stylecop_errors = CONFIGURATION != 'Release'
  puts "Treat StyleCop warnings as errors: #{ignore_stylecop_errors}"

  msb.properties = {:Configuration => CONFIGURATION, :StyleCopTreatErrorsAsWarnings => ignore_stylecop_errors}

  msb.parameters "/l:FileLogger,Microsoft.Build;logfile=#{OUTPUT}/msbuild.log"
end

desc "Checks .csproj files for StyleCop.MSBuild target"
task :verify_stylecop_msbuild do
  projectFiles = FileList["./**/*.csproj"]
  projectFiles.each{|f|
    doc = Nokogiri::XML(File.open(f))
    target = doc.css('PropertyGroup > StyleCopMSBuildTargetsFile')
    if (target.empty?)
      raise "'#{f}' does not have a StyleCop.MSBuild Target.\nPlease run 'Install-Package StyleCop.MSBuild' from the Package Manager Console Window within Visual Studio for this Project."
  end
  }
end

desc 'Run octopack'
task :octopack do
  package_version = ENV["PACKAGE_VERSION"]
  if !package_version
    raise "PACKAGE_VERSION not specified"
  end
  
  puts "PACKAGE_VERSION:        #{package_version}"
  msb = MSBuild.new
  msb.targets = [:Build]
  msb.properties = {:Configuration => CONFIGURATION, :RunOctoPack => true, :OctoPackPackageVersion => package_version}
  msb.verbosity = :minimal
  msb.nologo

  OCTOPUS_PROJECTS.each do |project|
    cs_proj = "#{SLN_DIR}/#{project}/#{project}.csproj"
    msb.parameters "/l:FileLogger,Microsoft.Build;logfile=#{OUTPUT}/msbuild.#{project}.log"
    msb.solution = cs_proj
    msb.execute
  end

  if not File.directory? OUTPUT
    mkpath(OUTPUT)
  end

  octopack_output = File.join(OUTPUT, "packages")
  if not File.directory? octopack_output
    mkpath(octopack_output) 
  end

  FileList["#{SLN_DIR}/**/obj/octopacked/*.nupkg"].each do |package|
    FileUtils.copy(package, octopack_output)
  end
end

desc 'Run xunit tests'
xunit :test do |x|

  x.log_level = :verbose

  if (!File.file?(XUNIT_RUNNER))
    Rake::Task[:restore ].execute() #download xunit console runner if not present
  end

  if (UNIT_TESTS.empty?)
    raise "Unable to locate any test projects"
  end

  assemblies = UNIT_TESTS.map{|x| "#{Pathname.new(x).dirname}/bin/#{CONFIGURATION}/#{Pathname.new(x).basename}".sub!(/.csproj/,'.dll')}
  puts assemblies.map {|x| " " + x}

  x.command = XUNIT_RUNNER
  x.assemblies = assemblies

  test_output = File.join(OUTPUT, "tests")

  if not File.directory? test_output
    mkpath(test_output) 
  end

  x.html_output = test_output
  x.skip_test_failures
  x.options = ["/teamcity"] if ENV["teamcity.dotnet.nunitlauncher"]
end


desc 'Run xunit tests with coverage'
task :coverage do
  if ENV["BUILD_NUMBER"]
    UNIT_TESTS.each do |assembly|
      puts "Covering #{assembly}"
      Rake::Task[:unitTestWithCoverage].execute(assembly)
      Rake::Task[:outputCoverageServiceMessage].execute(assembly)
    end
  else
    raise "Not TeamCity build - no DotCover avaialable"
  end
end

exec :unitTestWithCoverage, [:testAssembly] do |cmd, testAssembly|
  testAssemblyFullPath = Pathname.new(testAssembly).realpath
  testAssemblyName = File.basename(testAssemblyFullPath)
  cmd.command = @dotCoverFullPath
  cmd.parameters = [
    "cover",
    "/AnalyseTargetArguments=False",
    "/TargetExecutable=#{@xUnitRunnerFullPath}",
    "/TargetArguments=#{testAssemblyFullPath}",
    "/Output=#{@testResultFullPath}/#{testAssemblyName}.dcvr"
  ]
end

task :outputCoverageServiceMessage, [:testAssembly] do |t, testAssembly|
  testAssemblyFullPath = Pathname.new(testAssembly).realpath
  testAssemblyName = File.basename(testAssemblyFullPath)
  puts "##teamcity[importData type='dotNetCoverage' tool='dotcover' path='#{@testResultFullPath}/#{testAssemblyName}.dcvr']"
end

