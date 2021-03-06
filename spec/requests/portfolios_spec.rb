describe 'Portfolios API' do
  around do |example|
    bypass_rbac do
      example.call
    end
  end

  let(:tenant) { create(:tenant) }
  let!(:portfolio)            { create(:portfolio, :tenant_id => tenant.id) }
  let!(:portfolio_item)       { create(:portfolio_item, :tenant_id => tenant.id) }
  let!(:portfolio_items)      { portfolio.portfolio_items << portfolio_item }
  let(:portfolio_id)          { portfolio.id }
  let(:portfolio_item_id)     { portfolio_items.first.id }
  let(:new_portfolio_item_id) { portfolio_item.id }

  describe "GET /portfolios/:portfolio_id" do
    before do
      get "#{api}/portfolios/#{portfolio_id}", :headers => default_headers
    end

    context 'when portfolios exist' do
      it 'returns status code 200' do
        expect(response).to have_http_status(200)
      end

      it 'returns portfolio requested' do
        expect(json).not_to be_empty
        expect(json['id']).to eq(portfolio_id.to_s)
        expect(json['created_at']).to eq(portfolio.created_at.iso8601)
      end
    end
  end

  describe "GET v1.0 /portfolios/:portfolio_id" do
    before do
      get "#{api}/portfolios/#{portfolio_id}", :headers => default_headers
    end

    context 'when portfolios exist' do
      it 'returns status code 200' do
        expect(response).to have_http_status(200)
      end

      it 'returns portfolio requested' do
        expect(json).not_to be_empty
        expect(json['id']).to eq(portfolio_id.to_s)
      end
    end
  end

  describe "GET /portfolios/:portfolio_id/portfolio_items" do
    before do
      get "#{api}/portfolios/#{portfolio_id}/portfolio_items", :headers => default_headers
    end

    it 'returns all associated portfolio_items' do
      expect(json).not_to be_empty
      expect(json['meta']['count']).to eq 1
      portfolio_item_ids = portfolio_items.map { |x| x.id.to_s }.sort
      expect(json['data'].map { |x| x['id'] }.sort).to eq portfolio_item_ids
    end
  end

  describe "GET /portfolios_items/:portfolio_item_id" do
    before do
      get "#{api}/portfolio_items/#{portfolio_item_id}", :headers => default_headers
    end

    it 'returns an associated portfolio_item for a specific portfolio' do
      expect(json).not_to be_empty
      expect(json['id']).to eq portfolio_item_id.to_s
    end
  end

  describe "POST /portfolios/:portfolio_id/portfolio_items" do
    let(:params) { {:portfolio_item_id => portfolio_item.id} }
    before do
      post "#{api}/portfolios/#{portfolio.id}/portfolio_items", :params => params, :headers => default_headers
    end

    it 'returns a 200' do
      expect(response).to have_http_status(200)
    end

    it 'returns the portfolio_item which now points back to the portfolio' do
      expect(json.size).to eq 1
      expect(json.first['portfolio_id']).to eq portfolio.id.to_s
    end
  end

  describe "GET /portfolios" do
    context "without filter" do
      before do
        get "#{api}/portfolios", :headers => default_headers
      end

      context 'when portfolios exist' do
        it 'returns status code 200' do
          expect(response).to have_http_status(200)
        end

        it 'returns all portfolio requests' do
          expect(json['data'].size).to eq(1)
        end
      end
    end

    context "with filter" do
      let!(:portfolio_filter1) { create(:portfolio, :tenant_id => tenant.id, :name => "testfilter1") }
      let!(:portfolio_filter2) { create(:portfolio, :tenant_id => tenant.id, :name => "testfilter2") }

      it 'returns only the id specified in the filter' do
        get "#{api}/portfolios?filter[id]=#{portfolio_id}", :headers => default_headers

        expect(json["meta"]["count"]).to eq 1
        expect(json["data"].first["id"]).to eq portfolio_id.to_s
      end

      it 'allows filtering by name via regex' do
        get "#{api}/portfolios?filter[name][starts_with]=test", :headers => default_headers

        expect(json["meta"]["count"]).to eq 2

        names = json["data"].each.collect { |item| item["name"] }
        expect(names).to match_array [portfolio_filter1.name, portfolio_filter2.name]
      end
    end
  end

  describe '/portfolios', :type => :routing do
    let(:valid_attributes) { { :name => 'rspec 1', :description => 'rspec 1 description' } }
    context 'with wrong header' do
      it 'returns a 404' do
        expect(:post => "/portfolios").not_to be_routable
      end
    end
  end

  describe 'DELETE /portfolios/:portfolio_id' do
    let(:valid_attributes) { { :name => 'PatchPortfolio', :description => 'description for patched portfolio' } }

    context 'when discarding a portfolio' do
      before do
        delete "#{api}/portfolios/#{portfolio_id}", :headers => default_headers, :params => valid_attributes
      end

      it 'deletes the record' do
        expect(response).to have_http_status(204)
      end

      it 'sets the discarded_at column' do
        expect(Portfolio.with_discarded.find_by(:id => portfolio_id).discarded_at).to_not be_nil
      end

      it "cannot be requested" do
        expect { get("/#{api}/portfolios/#{portfolio_id}", :headers => default_headers) }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it 'allows adding portfolios with the same name when one is discarded' do
        post "#{api}/portfolios", :headers => default_headers, :params => valid_attributes

        expect(response).to have_http_status(:ok)
      end
    end

    context "when discarding portfolio_items fails" do
      before do
        allow(Portfolio).to receive(:find).with(portfolio.id.to_s).and_return(portfolio)
        allow(portfolio_item).to receive(:discard).and_return(false)
      end

      it 'reports errors when discarding child portfolio_items fails' do
        delete "#{api}/portfolios/#{portfolio_id}", :headers => default_headers, :params => valid_attributes

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'PATCH /portfolios/:portfolio_id' do
    let(:valid_attributes) { { :name => 'PatchPortfolio', :description => 'description for patched portfolio', :workflow_ref => "123456" } }
    let(:invalid_attributes) { { :fred => 'nope', :bob => 'bob portfolio' } }
    context 'when patched portfolio is valid' do
      before do
        patch "#{api}/portfolios/#{portfolio_id}", :headers => default_headers, :params => valid_attributes
      end

      it 'returns status code 200' do
        expect(response).to have_http_status(200)
      end

      it 'returns an updated portfolio object' do
        expect(json).not_to be_empty
        expect(json).to be_a Hash
        expect(json['name']).to eq valid_attributes[:name]
      end
    end

    context 'when patched portfolio params are invalid' do
      before do
        patch "#{api}/portfolios/#{portfolio_id}", :headers => default_headers, :params => invalid_attributes
      end

      it 'returns status code 200' do
        expect(response).to have_http_status(200)
      end

      it 'returns an updated portfolio object' do
        expect(json).not_to be_empty
        expect(json).to be_a Hash
        expect(json['name']).to_not eq invalid_attributes[:name]
      end
    end
  end

  describe 'POST /portfolios' do
    let(:valid_attributes) { { :name => 'rspec 1', :description => 'rspec 1 description' } }
    context 'when portfolio attributes are valid' do
      before { post "#{api}/portfolios", :params => valid_attributes, :headers => default_headers }

      it 'returns status code 200' do
        expect(response).to have_http_status(200)
      end

      it 'returns the new portfolio' do
        expect(json['name']).to eq valid_attributes[:name]
      end

      it 'returns a status code 422 when trying to create with the same name' do
        post "#{api}/portfolios", :params => valid_attributes, :headers => default_headers

        expect(response).to have_http_status(422)
      end

      it 'stores the username in the owner column' do
        expect(json['owner']).to eq default_username
      end
    end

    RSpec.shared_context "sharing_objects" do
      let(:group_uuids) { %w[1 2 3] }
      let(:permissions) { %w[read] }
      let(:app_name) { "catalog" }
    end

    context 'share' do
      include_context "sharing_objects"
      let(:sharing_attributes) { {:group_uuids => group_uuids, :permissions => permissions} }
      let(:dummy) { double("RBAC::ShareResource", :process => self) }
      it "portfolio" do
        with_modified_env :APP_NAME => app_name do
          options = {:app_name      => app_name,
                     :resource_ids  => [portfolio.id.to_s],
                     :resource_name => 'portfolios',
                     :permissions   => permissions,
                     :group_uuids   => group_uuids}
          expect(RBAC::ShareResource).to receive(:new).with(options).and_return(dummy)
          post "#{api}/portfolios/#{portfolio.id}/share", :params => sharing_attributes, :headers => default_headers
          expect(response).to have_http_status(204)
        end
      end
    end

    context 'unshare' do
      include_context "sharing_objects"
      let(:unsharing_attributes) { {:group_uuids => group_uuids, :permissions => permissions} }
      let(:dummy) { double("RBAC::UnshareResource", :process => self) }
      it "portfolio" do
        with_modified_env :APP_NAME => app_name do
          options = {:app_name      => app_name,
                     :resource_ids  => [portfolio.id.to_s],
                     :resource_name => 'portfolios',
                     :permissions   => permissions,
                     :group_uuids   => group_uuids}
          expect(RBAC::UnshareResource).to receive(:new).with(options).and_return(dummy)
          post "#{api}/portfolios/#{portfolio.id}/unshare", :params => unsharing_attributes, :headers => default_headers
          expect(response).to have_http_status(204)
        end
      end
    end

    context 'share_info' do
      include_context "sharing_objects"
      let(:dummy_response) { double(:share_info => {'a' => 1}) }
      let(:dummy) { double("RBAC::UnshareResource", :process => dummy_response) }
      it "portfolio" do
        with_modified_env :APP_NAME => app_name do
          options = {:app_name      => app_name,
                     :resource_id   => portfolio.id.to_s,
                     :resource_name => 'portfolios'}
          expect(RBAC::QuerySharedResource).to receive(:new).with(options).and_return(dummy)
          get "#{api}/portfolios/#{portfolio.id}/share_info", :headers => default_headers

          expect(response).to have_http_status(200)
        end
      end
    end
  end
end
