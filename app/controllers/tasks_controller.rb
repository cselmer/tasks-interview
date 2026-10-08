class TasksController < ApplicationController
  before_action :authenticate_user

  def index
    load_tasks
    @task = Task.new
  end

  def edit
    @task = Task.find(params[:id])
  end

  def create
    @task = Task.new(task_params)

    if @task.save
      redirect_to tasks_path
    else
      load_tasks
      render :index, status: :unprocessable_content
    end
  end

  def update
    @task = Task.find(params[:id])

    if @task.update(task_params)
      redirect_to tasks_path
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @task = Task.find(params[:id])

    if @task.destroy
      redirect_to tasks_path
    else
      redirect_to tasks_path, alert: "Could not delete task."
    end
  end

  private

  def load_tasks
    @tasks = Task.order(:created_at)
  end

  def task_params
    params.require(:task).permit(:title, :description, :complete)
  end
end
