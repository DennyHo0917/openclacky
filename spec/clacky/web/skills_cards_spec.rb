# frozen_string_literal: true

RSpec.describe "Skills card grid UI" do
  let(:web_dir) { File.expand_path("../../../lib/clacky/web", __dir__) }
  let(:view)    { File.read(File.join(web_dir, "features/skills/view.js")) }
  let(:styles)  { File.read(File.join(web_dir, "app.css")) }

  it "renders both tabs as logo-free cards in one grid" do
    expect(view).to include('tile.className = "skill-tile"')
    expect(view).to include('grid.className = "skill-grid"')
    expect(view).to include("_grid(brandSkills.map(_renderBrandSkillTile))")
    expect(view).not_to include("letterIcon")
    expect(view).not_to include("brand-skill-card")
    expect(styles).not_to include(".brand-skill-card")
  end

  it "groups system and custom skills like the extension publishers" do
    expect(view).to include('{ title: I18n.t("skills.badge.system"), items: visible.filter(_isSystem) }')
    expect(view).to include('{ title: I18n.t("skills.badge.custom"), items: visible.filter(s => !_isSystem(s)) }')
  end

  it "shows a check that turns into a use button on hover" do
    expect(view).to include('class="skill-tile-use-done"')
    expect(view).to include('class="skill-tile-use-go"')
    expect(styles).to include(".skill-tile:hover .skill-tile-use-go")
  end

  it "moves enable/disable, edit and delete into the … menu" do
    expect(view).to include('label: I18n.t("extensions.action.disable")')
    expect(view).to include('label: I18n.t("skills.btn.edit")')
    expect(view).to include('label: I18n.t("skills.btn.delete"), run: () => Skills.delete(skill.name), danger: true')
    expect(view).not_to include("skill-toggle-input")
    expect(styles).not_to include(".skill-toggle-track")
  end

  it "gives brand skills install / update / use states" do
    expect(view).to include('class="ext-row-add skill-tile-install"')
    expect(view).to include("skill-tile-install skill-tile-update")
    expect(view).to include("Skills.deleteBrandSkill(name)")
  end

  it "opens a #skills/<name> detail page with preview and source modes" do
    app = File.read(File.join(web_dir, "app.js"))
    expect(app).to include("const mSkillDetail = path.match(/^skills\\/(brand\\/)?(.+)$/);")
    expect(app).to include("Skills.onPanelShow({ detailName: params.detailName || null, brand: !!params.brand });")
    expect(view).to include('router.navigate("skills", { detailName: name, brand })')
    expect(view).to include('data-skill-mode="${mode}"')
    expect(view).to include("renderer.html = ({ text: raw }) => escapeHtml(raw);")
    expect(File.read(File.join(web_dir, "index.html"))).to include('<div id="skills-detail" class="skill-detail"')
  end

  it "opens brand skills in the same detail page via #skills/brand/<name>" do
    expect(view).to include("_openDetail(name, true);")
    expect(view).to include("if (_detailBrand) return _renderBrandDetail(panel);")
    expect(view).to include('id="skill-detail-install"')
    expect(view).to include('"skills.detail.encrypted"')
    expect(view).to include("latest.release_notes")
    expect(File.read(File.join(web_dir, "features/skills/store.js"))).to include("get brandLoaded()")
  end
end
