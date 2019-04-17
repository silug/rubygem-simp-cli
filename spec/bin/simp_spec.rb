require 'spec_helper'
require 'timeout'
require 'tmpdir'

def execute(command, input_file = nil)
  log_tmp_dir = Dir.mktmpdir( File.basename( __FILE__ ) )
  stdout_file = File.join(log_tmp_dir,'stdout.txt')
  stderr_file = File.join(log_tmp_dir,'stderr.txt')
  if input_file
    spawn_args = [:out => stdout_file, :err => stderr_file, :in => input_file]
  else
    spawn_args = [:out => stdout_file, :err => stderr_file]
  end
  pid = spawn(command, *spawn_args)

  # in case we have screwed up our test
  Timeout::timeout(30) { Process.wait(pid) }
  exitstatus = $?.nil? ? nil : $?.exitstatus
  stdout = IO.read(stdout_file) if File.exists?(stdout_file)
  if File.exists?(stderr_file)
    stderr_raw = IO.read(stderr_file)
    # WORKAROUND
    stderr = stderr_raw.split("\n").delete_if do |line|
      # When we are running this test on a system in which
      # /opt/puppetlabs/puppet/lib/ruby exists and our environment
      # points to a different ruby (e.g., rvm), multiple rubies will
      # be in the Ruby load path due to kludgey logic in bin/simp.
      # This causes problems. For example, we will get warnings
      # about already initialized constants in pathname.rb.
      line.include?('warning: already initialized constant') or
      line.include?('warning: previous definition of')
    end.join("\n")
  end
  { :exitstatus => exitstatus, :stdout => stdout, :stderr => stderr }
ensure
  FileUtils.remove_entry_secure(log_tmp_dir) if log_tmp_dir
end

def execute_and_signal(command, signal_type)
  log_tmp_dir = Dir.mktmpdir( File.basename( __FILE__ ) )
  stdout_file = File.join(log_tmp_dir,'stdout.txt')
  stderr_file = File.join(log_tmp_dir,'stderr.txt')
  pipe_r, pipe_w = IO.pipe
  pid = spawn(command, :out => stdout_file, :err => stderr_file, :in => pipe_r)
  pipe_r.close

  # Wait for bytes on stdout.txt, as this tells us the spawned process
  # is up
  Timeout::timeout(30) {
    while File.size(stdout_file) == 0
      sleep 0.5
    end
  }

  Process.kill(signal_type, pid)
  Timeout::timeout(10) { Process.wait(pid) }
  exitstatus = $?.nil? ? nil : $?.exitstatus
  stdout = IO.read(stdout_file) if File.exists?(stdout_file)
  stderr = IO.read(stderr_file) if File.exists?(stderr_file)
  pipe_w.close
  { :exitstatus => exitstatus, :stdout => stdout, :stderr => stderr }
ensure
  FileUtils.remove_entry_secure(log_tmp_dir) if log_tmp_dir
end

# Since most of the functionality will be tested in unit tests,
# this suite is simply to test that class executed within simp
# is hooked in properly:
# - accepts command line arguments
# - returns processing status
# - reads from stdin appropriately
# - handles stdin termination signals appropriately
# - outputs to stdout and stderr appropriately
describe 'simp executable' do
  let(:simp_exe) { File.expand_path('../../bin/simp', __dir__) }

  before :all do
    env_files_dir = File.expand_path('../lib/simp/cli/commands/files', __dir__)
    code_dir = File.expand_path('.puppetlabs/etc/code',ENV['HOME'])
    @test_env_dir = File.join(code_dir, 'environments')
    FileUtils.mkdir_p(@test_env_dir)

# FIXME without :verbose option, copy doesn't copy all....
    FileUtils.cp_r(File.expand_path('environments/simp', env_files_dir), @test_env_dir, :verbose => true)
  end

  before :each do
    @tmp_dir = Dir.mktmpdir( File.basename( __FILE__ ) )
    @simp_config_args = [
      '--dry-run',  # do NOT inadvertently make any changes on the test system
      '-o', File.join(@tmp_dir, 'simp_conf.yaml'),
      '-p', File.join(@tmp_dir, 'simp_config_settings.yaml'),
      '-l', File.join(@tmp_dir, 'simp_config.log')
      ].join(' ')
  end

  after :each do
    FileUtils.remove_entry_secure(@tmp_dir) if @tmp_dir
  end

  after :all do
    FileUtils.remove_entry_secure(@test_env_dir)
  end

  context 'when run' do
    it 'handles lack of command line arguments' do
      results = execute(simp_exe)
      expect(results[:exitstatus]).to eq 0
      expect(results[:stdout]).to match(/Usage: simp \[command\]/)
      expect(results[:stderr]).to be_empty
    end

    it 'handles command line arguments' do
      results = execute("#{simp_exe} config -h")
      expect(results[:exitstatus]).to eq 0
      expect(results[:stdout]).to match(/=== The SIMP Configuration Tool ===/)
      expect(results[:stderr]).to be_empty
    end

=begin
FIXME
This test now requires the modern 'networking' fact, which is not
available with Facter 2.x, an old version required by simp-rake-helpers.
Re-enable when this gets worked out.
    it 'processes console input' do
      stdin_file = File.expand_path('files/simp_config_full_stdin_file', __dir__)
      results = execute("#{simp_exe} config #{@simp_config_args}", stdin_file)
      if results[:exitstatus] != 0
        puts '=============stdout===================='
        puts results[:stdout]
        puts '=============stderr===================='
        puts results[:stderr]
      end
      expect(results[:exitstatus]).to eq 0
      expect(results[:stdout].size).not_to eq 0
      #TODO better validation?
      #FIXME  stderr is full of the following messages
      #   "stty: 'standard input': Inappropriate ioctl for device"
      #   From pipes within exec'd code?
    end
=end

    it 'gracefully handles console input termination' do
      stdin_file = File.expand_path('files/simp_config_trunc_stdin_file', __dir__)
      results = execute("#{simp_exe} config #{@simp_config_args}", stdin_file)
      expect(results[:exitstatus]).to eq 1
      expect(results[:stderr]).to match(/Input terminated! Exiting/)
    end

    it 'gracefully handles program interrupt' do
      command = "#{simp_exe} config #{@simp_config_args}"
      results = execute_and_signal(command, 'INT')
      # WORKAROUND
      # When we are running this test on a system in which
      # /opt/puppetlabs/puppet/lib/ruby exists and our environment
      # points to a different ruby (e.g., rvm), multiple rubies will
      # be in the Ruby load path due to kludgey logic in bin/simp.
      # This causes problems. For this test, the SIGINT is not delivered
      # to cli.rb.  The program exits with a status of uncaught SIGINT and
      # a nil exit status.
      unless results[:exitstatus].nil?
        expect(results[:exitstatus]).to eq 1
        expect(results[:stderr]).to match(/Processing interrupted! Exiting/)
      end
    end

    it 'handles other program-terminating signals' do
      command = "#{simp_exe} config #{@simp_config_args}"
      results = execute_and_signal(command, 'HUP')
      expect(results[:exitstatus]).to eq 1
      expect(results[:stderr]).to match(/Process received signal SIGHUP. Exiting/)
    end

    it 'reports processing failures' do
      results = execute("#{simp_exe} bootstrap --oops")
      expect(results[:exitstatus]).to eq 1
      expect(results[:stdout]).to be_empty
      expect(results[:stderr]).to match(
        /'bootstrap' command options error: invalid option: --oops/)
    end
  end
end
