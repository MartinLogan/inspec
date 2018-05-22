class AwsElbs < Inspec.resource(1)
  name 'aws_elbs'
  desc 'Verifies settings for AWS ELBs (classic Elastic Load Balancers) in bulk'
  example '
    describe aws_elbs do
      it { should exist }
    end
  '
  supports platform: 'aws'

  include AwsPluralResourceMixin
  def validate_params(resource_params)
    unless resource_params.empty?
      raise ArgumentError, 'aws_elbs does not accept resource parameters.'
    end
    resource_params
  end

  # Underlying FilterTable implementation.
  filter = FilterTable.create
  filter.add_accessor(:entries)
        .add_accessor(:where)
        .add(:exists?) { |table| !table.params.empty? }
        .add(:count) { |table| table.params.count }
        .add(:availability_zones, field: :availability_zones, type: :simple)
        .add(:dns_names, field: :dns_name)
        .add(:external_ports, field: :external_ports, type: :simple)
        .add(:instance_ids, field: :instance_ids, type: :simple)        
        .add(:internal_ports, field: :internal_ports, type: :simple)
        .add(:names, field: :name)
        .add(:security_group_ids, field: :security_group_ids, type: :simple)
        .add(:subnet_ids, field: :subnet_ids, type: :simple)
        .add(:vpc_ids, field: :vpc_id)
  filter.connect(self, :table)

  def to_s
    'AWS ELBs'
  end

  def fetch_from_api
    backend = BackendFactory.create(inspec_runner)
    @table = []
    pagination_opts = {}
    loop do
      api_result = backend.describe_load_balancers(pagination_opts)
      @table += unpack_describe_elbs_response(api_result.load_balancer_descriptions)
      break unless api_result.next_marker
      pagination_opts = { marker: api_result.next_marker }
    end
  end

  def unpack_describe_elbs_response(load_balancers)
    load_balancers.map do |lb_struct|
      {
        availability_zones: lb_struct.availability_zones,
        dns_name: lb_struct.dns_name,
        external_ports: lb_struct.listener_descriptions.map {|ld| ld.listener.load_balancer_port },
        instance_ids: lb_struct.instances.map {|i| i.instance_id },
        internal_ports: lb_struct.listener_descriptions.map {|ld| ld.listener.instance_port },
        name: lb_struct.load_balancer_name,
        security_group_ids: lb_struct.security_groups,
        subnet_ids: lb_struct.subnets,
        vpc_id: lb_struct.vpc_id,
      }
    end
  end

  class Backend
    class AwsClientApi < AwsBackendBase
      BackendFactory.set_default_backend(self)
      self.aws_client_class = Aws::ElasticLoadBalancing::Client

      def describe_load_balancers(query = {})
        aws_service_client.describe_load_balancers(query)
      end
    end
  end
end