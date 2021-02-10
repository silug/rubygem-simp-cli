require 'simp/cli/config/items/data/simp_options_ntp_servers'
require 'rspec/its'
require_relative '../spec_helper'

describe Simp::Cli::Config::Item::SimpOptionsNTPServers do
  before :all do
    @files_dir = File.expand_path( 'files', File.dirname( __FILE__ ) )
  end

  before :each do
    @ci = Simp::Cli::Config::Item::SimpOptionsNTPServers.new
    @ci.silent = true
  end

#  describe '#recommended_value' do
#  TODO: how to test this when os_value returns a valid value?
#    it 'recommends nil when network::gateway is unavailable' do
#      expect( @ci.recommended_value ).to be_nil
#    end
#  end

  describe '#validate' do
    it 'validates array with good hosts' do
      expect( @ci.validate ['pool.ntp.org'] ).to eq true
      expect( @ci.validate ['192.168.1.1'] ).to eq true
      expect( @ci.validate ['192.168.1.1', 'pool.ntp.org'] ).to eq true
      # NTP servers are optional, so nil is okay
      expect( @ci.validate nil   ).to eq true
    end

    it "doesn't validate array with bad hosts" do
      expect( @ci.validate 0     ).to eq false
      expect( @ci.validate false ).to eq false
      expect( @ci.validate [nil] ).to eq false
      expect( @ci.validate ['pool.ntp.org-'] ).to eq false
      expect( @ci.validate ['192.168.1.1.'] ).to eq false
      expect( @ci.validate ['1.2.3.4/24'] ).to eq false
    end

    it 'accepts an empty list' do
      expect( @ci.validate [] ).to eq true
      expect( @ci.validate '' ).to eq true
    end
  end

  describe '#get_os_value' do
    before :all do
      @ntp_no_servers = File.join(@files_dir,'ntp.conf_no_servers')
      @chrony_no_servers = File.join(@files_dir,'chrony.conf_no_servers')
      @chrony_remote_servers = File.join(@files_dir,'chrony.conf_remote_servers')
      @ntp_remote_servers = File.join(@files_dir,'ntp.conf_remote_servers')
      @chrony_local_servers = File.join(@files_dir,'chrony.conf_local_servers')
      @ntp_local_servers = File.join(@files_dir,'ntp.conf_local_servers')
    end

    it 'returns empty array when chrony.conf has no servers and chrondy is running' do
      allow(Simp::Cli::Utils).to receive(:systemctl_running?).with('chronyd').and_return(true)
      expect( @ci.get_os_value(@chrony_no_servers, @ntp_no_servers)).to eq []
    end

    it 'returns empty array when ntp.conf has no servers and ntp is running' do
      allow(Simp::Cli::Utils).to receive(:systemctl_running?).with('ntpd').and_return(true)
      allow(Simp::Cli::Utils).to receive(:systemctl_running?).with('chronyd').and_return(false)
      expect( @ci.get_os_value(@chrony_no_servers, @ntp_no_servers)).to eq []
    end

    it 'returns chrony servers when chrony is running' do
      allow(Simp::Cli::Utils).to receive(:systemctl_running?).with('chronyd').and_return(true)
      allow(Simp::Cli::Utils).to receive(:systemctl_running?).with('ntpd').and_return(true)
      expected = [
        '0.chronyd.centos.pool.ntp.org',
        '1.chronyd.centos.pool.ntp.org'
      ]
      expect( @ci.get_os_value(@chrony_remote_servers,@ntp_remote_servers)).to eq expected
    end

    it 'returns ntpd servers when chrony is not running but ntpd is' do
      allow(Simp::Cli::Utils).to receive(:systemctl_running?).with('chronyd').and_return(false)
      allow(Simp::Cli::Utils).to receive(:systemctl_running?).with('ntpd').and_return(true)
      expected = [
        '0.ntpd.north-america.pool.ntp.org',
        '1.ntpd.north-america.pool.ntp.org'
      ]
      expect( @ci.get_os_value(@chrony_remote_servers,@ntp_remote_servers)).to eq expected
    end
    it 'returns empty array when it can not access the files' do
      allow(Simp::Cli::Utils).to receive(:systemctl_running?).with('chronyd').and_return(false)
      allow(Simp::Cli::Utils).to receive(:systemctl_running?).with('ntpd').and_return(false)
      expect( @ci.get_os_value('/not/there', '/not/there') ).to eq []
    end

    it 'returns empty array when local servers are in the chrony files' do
      allow(Simp::Cli::Utils).to receive(:systemctl_running?).with('chronyd').and_return(false)
      allow(Simp::Cli::Utils).to receive(:systemctl_running?).with('ntpd').and_return(false)
      expect( @ci.get_os_value(@chrony_local_servers,@ntp_remote_servers)).to eq []
    end

    it 'returns empty array when local servers are in the ntps files' do
      allow(Simp::Cli::Utils).to receive(:systemctl_running?).with('chronyd').and_return(false)
      allow(Simp::Cli::Utils).to receive(:systemctl_running?).with('ntpd').and_return(true)
      expect( @ci.get_os_value('/not/there',@ntp_local_servers)).to eq []
    end
    it 'returns the ntp servers when no services are running and no chrony file exists' do
      allow(Simp::Cli::Utils).to receive(:systemctl_running?).with('chronyd').and_return(false)
      allow(Simp::Cli::Utils).to receive(:systemctl_running?).with('ntpd').and_return(false)
      expected = [
        '0.ntpd.north-america.pool.ntp.org',
        '1.ntpd.north-america.pool.ntp.org'
      ]
      expect( @ci.get_os_value('/not/there',@ntp_remote_servers)).to eq expected
    end
  end

  it_behaves_like 'a child of Simp::Cli::Config::Item'
end
