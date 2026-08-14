ActiveAdmin.register_page "Organogram" do
  menu label: "Organogram", priority: 6

  content title: "Organogram" do
    roots, children = helpers.organogram_tree(User.employed)

    render partial: "shared/organogram",
           locals: { roots: roots, children: children, editable: true }
  end
end
